/// A lexer for Dart source, enough for syntactic facts (ADR-0017,
/// docs/specs/dart-toolchain.md, section 6).
library;

/// The kinds of token the lexer produces.
abstract final class TokenKind {
  /// An identifier or a keyword. The lexer has no keyword table.
  static const int word = 0;

  /// A number.
  static const int number = 1;

  /// A string, or one segment of an interpolated string.
  static const int string = 2;

  /// Punctuation or an operator, including the `$` and `${` that open an
  /// interpolation.
  static const int punctuation = 3;
}

/// The tokens of one source file.
///
/// Tokens are parallel lists, so a large file costs a few integers per
/// token instead of an object. Comments and whitespace are not tokens.
final class Lexed {
  /// Creates an empty result for [source]; [lex] fills it.
  new _(this.source);

  /// The text that was lexed.
  final String source;

  /// Where each token starts.
  final List<int> starts = [];

  /// Where each token ends, exclusive.
  final List<int> ends = [];

  /// The [TokenKind] of each token.
  final List<int> kinds = [];

  final List<int> _closers = [];

  /// False when the source has an unterminated string or block comment, or
  /// brackets that do not pair. The lexer carries on regardless; the flag
  /// says the answer is not to be trusted.
  bool balanced = true;

  /// The number of tokens.
  int get length => starts.length;

  /// The text of token [index].
  String lexeme(int index) => source.substring(starts[index], ends[index]);

  /// The text of every token, in order.
  List<String> get lexemes => [for (var i = 0; i < length; i++) lexeme(i)];

  /// The index of the bracket that closes the one at [index], or -1 when
  /// [index] is not an opening bracket or its closer is missing.
  int closerOf(int index) => _closers[index];

  void _add(int start, int end, int kind) {
    starts.add(start);
    ends.add(end);
    kinds.add(kind);
    _closers.add(-1);
  }
}

bool _isLetter(int c) =>
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x41 && c <= 0x5A) ||
    c == 0x5F ||
    c == 0x24;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isHex(int c) =>
    _isDigit(c) || (c >= 0x61 && c <= 0x66) || (c >= 0x41 && c <= 0x46);

const _quote = 0x27;
const _doubleQuote = 0x22;
const _backslash = 0x5C;
const _dollar = 0x24;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;

/// Lexes [source] the way the Dart scanner tokenizes it, minus the keyword
/// table, so the lexemes can be hashed (a declaration's `tokenHash` is
/// defined on them).
///
/// The Dart scanner's own choices are followed where they show in a
/// lexeme: `>>` is one token, `[]` and `[]=` are one token, and an
/// interpolated string is split at each `$`, with an empty segment between
/// two interpolations.
///
/// It never throws. It uses no recursion, so nesting depth cannot overflow
/// the stack: open brackets and interpolations live on explicit stacks.
/// Every loop advances through the source, so the cost is linear in its
/// length (security S6).
Lexed lex(String source) {
  final out = Lexed._(source);
  final n = source.length;
  var i = 0;
  if (source.startsWith('#!')) {
    while (i < n && source.codeUnitAt(i) != 0x0A) {
      i++;
    }
  }
  // Open brackets: the token index of each, and for `${` the string to
  // resume when it closes (the quote code, plus 0x100 when triple); 0 for
  // the other brackets.
  final open = <int>[];
  final resume = <int>[];

  // Pops the bracket closed by [closer] and returns its resume value.
  int close(int index, int closer) {
    if (open.isEmpty) {
      out.balanced = false;
      return 0;
    }
    final at = open.removeLast();
    final resumes = resume.removeLast();
    final opener = source.codeUnitAt(out.starts[at]);
    final matches = switch (closer) {
      0x29 => opener == 0x28,
      0x5D => opener == 0x5B,
      _ => opener == _openBrace || opener == _dollar,
    };
    if (!matches) out.balanced = false;
    out._closers[at] = index;
    return resumes;
  }

  // Scans a string whose current segment starts at [segmentStart], with
  // [from] at its first content character. Returns the offset after it,
  // negated when it stopped inside a `${` (the expression is lexed by the
  // main loop).
  int string(
    int segmentStart,
    int from,
    int quote, {
    required bool triple,
    required bool raw,
  }) {
    var start = segmentStart;
    var j = from;
    while (j < n) {
      final c = source.codeUnitAt(j);
      if (c == _backslash && !raw) {
        j += 2;
        continue;
      }
      if (c == quote) {
        if (!triple) {
          out._add(start, j + 1, TokenKind.string);
          return j + 1;
        }
        if (j + 2 < n &&
            source.codeUnitAt(j + 1) == quote &&
            source.codeUnitAt(j + 2) == quote) {
          out._add(start, j + 3, TokenKind.string);
          return j + 3;
        }
      } else if (!triple && (c == 0x0A || c == 0x0D)) {
        out
          ..balanced = false
          .._add(start, j, TokenKind.string);
        return j;
      } else if (c == _dollar && !raw && j + 1 < n) {
        final next = source.codeUnitAt(j + 1);
        if (next == _openBrace) {
          out
            .._add(start, j, TokenKind.string)
            .._add(j, j + 2, TokenKind.punctuation);
          open.add(out.length - 1);
          resume.add(quote | (triple ? 0x100 : 0));
          return -(j + 2);
        }
        if (_isLetter(next) && next != _dollar) {
          out
            .._add(start, j, TokenKind.string)
            .._add(j, j + 1, TokenKind.punctuation);
          var k = j + 1;
          while (k < n) {
            final d = source.codeUnitAt(k);
            if ((_isLetter(d) && d != _dollar) || _isDigit(d)) {
              k++;
            } else {
              break;
            }
          }
          out._add(j + 1, k, TokenKind.word);
          start = k;
          j = k;
          continue;
        }
      }
      j++;
    }
    out
      ..balanced = false
      .._add(start, n, TokenKind.string);
    return n;
  }

  // A run of digits; `_` between digits is a separator.
  int digits(int from) {
    var j = from;
    while (j < n) {
      final d = source.codeUnitAt(j);
      if (_isDigit(d) ||
          (d == 0x5F && j + 1 < n && _isDigit(source.codeUnitAt(j + 1)))) {
        j++;
      } else {
        break;
      }
    }
    return j;
  }

  while (i < n) {
    final c = source.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
    } else if (c == 0x2F && i + 1 < n && source.codeUnitAt(i + 1) == 0x2F) {
      while (i < n && source.codeUnitAt(i) != 0x0A) {
        i++;
      }
    } else if (c == 0x2F && i + 1 < n && source.codeUnitAt(i + 1) == 0x2A) {
      var depth = 0;
      var closed = false;
      while (i < n) {
        if (source.codeUnitAt(i) == 0x2F &&
            i + 1 < n &&
            source.codeUnitAt(i + 1) == 0x2A) {
          depth++;
          i += 2;
        } else if (source.codeUnitAt(i) == 0x2A &&
            i + 1 < n &&
            source.codeUnitAt(i + 1) == 0x2F) {
          depth--;
          i += 2;
          if (depth == 0) {
            closed = true;
            break;
          }
        } else {
          i++;
        }
      }
      if (!closed) out.balanced = false;
    } else if (c == _quote || c == _doubleQuote) {
      final triple =
          i + 2 < n &&
          source.codeUnitAt(i + 1) == c &&
          source.codeUnitAt(i + 2) == c;
      final next = string(
        i,
        i + (triple ? 3 : 1),
        c,
        triple: triple,
        raw: false,
      );
      i = next < 0 ? -next : next;
    } else if (_isLetter(c)) {
      final start = i;
      while (i < n) {
        final d = source.codeUnitAt(i);
        if (_isLetter(d) || _isDigit(d)) {
          i++;
        } else {
          break;
        }
      }
      final isRawPrefix =
          i == start + 1 &&
          c == 0x72 &&
          i < n &&
          (source.codeUnitAt(i) == _quote ||
              source.codeUnitAt(i) == _doubleQuote);
      if (isRawPrefix) {
        final quote = source.codeUnitAt(i);
        final triple =
            i + 2 < n &&
            source.codeUnitAt(i + 1) == quote &&
            source.codeUnitAt(i + 2) == quote;
        i = string(
          start,
          i + (triple ? 3 : 1),
          quote,
          triple: triple,
          raw: true,
        );
      } else {
        out._add(start, i, TokenKind.word);
      }
    } else if (_isDigit(c) ||
        (c == 0x2E && i + 1 < n && _isDigit(source.codeUnitAt(i + 1)))) {
      final start = i;
      if (c == 0x30 &&
          i + 1 < n &&
          (source.codeUnitAt(i + 1) == 0x78 ||
              source.codeUnitAt(i + 1) == 0x58)) {
        i += 2;
        while (i < n &&
            (_isHex(source.codeUnitAt(i)) ||
                (source.codeUnitAt(i) == 0x5F &&
                    i + 1 < n &&
                    _isHex(source.codeUnitAt(i + 1))))) {
          i++;
        }
      } else {
        i = digits(i);
        if (i + 1 < n &&
            source.codeUnitAt(i) == 0x2E &&
            _isDigit(source.codeUnitAt(i + 1))) {
          i = digits(i + 1);
        }
        if (i < n &&
            (source.codeUnitAt(i) == 0x65 || source.codeUnitAt(i) == 0x45)) {
          var j = i + 1;
          if (j < n &&
              (source.codeUnitAt(j) == 0x2B || source.codeUnitAt(j) == 0x2D)) {
            j++;
          }
          if (j < n && _isDigit(source.codeUnitAt(j))) i = digits(j);
        }
      }
      out._add(start, i, TokenKind.number);
    } else {
      final length = _punctuationLength(source, i, n);
      final index = out.length;
      out._add(i, i + length, TokenKind.punctuation);
      i += length;
      if (length != 1) continue;
      switch (c) {
        case 0x28 || 0x5B || _openBrace:
          open.add(index);
          resume.add(0);
        case 0x29 || 0x5D:
          close(index, c);
        case _closeBrace:
          final resumes = close(index, c);
          if (resumes != 0) {
            final next = string(
              i,
              i,
              resumes & 0xFF,
              triple: (resumes & 0x100) != 0,
              raw: false,
            );
            i = next < 0 ? -next : next;
          }
      }
    }
  }
  if (open.isNotEmpty) out.balanced = false;
  return out;
}

/// How many characters of the operator at [i] belong to one token: the
/// longest match.
int _punctuationLength(String s, int i, int n) {
  final c = s.codeUnitAt(i);
  int at(int k) => i + k < n ? s.codeUnitAt(i + k) : -1;
  switch (c) {
    case 0x3F: // ?
      if (at(1) == 0x3F) return at(2) == 0x3D ? 3 : 2;
      if (at(1) == 0x2E) return at(2) == 0x2E ? 3 : 2;
      return 1;
    case 0x2E: // .
      if (at(1) == 0x2E) {
        if (at(2) == 0x2E) return at(3) == 0x3F ? 4 : 3;
        return 2;
      }
      return 1;
    case 0x3D: // =
      return at(1) == 0x3D || at(1) == 0x3E ? 2 : 1;
    case 0x21: // !
      return at(1) == 0x3D ? 2 : 1;
    case 0x3C: // <
      if (at(1) == 0x3C) return at(2) == 0x3D ? 3 : 2;
      return at(1) == 0x3D ? 2 : 1;
    case 0x3E: // >
      if (at(1) == 0x3E) {
        if (at(2) == 0x3E) return at(3) == 0x3D ? 4 : 3;
        return at(2) == 0x3D ? 3 : 2;
      }
      return at(1) == 0x3D ? 2 : 1;
    case 0x2B: // +
      return at(1) == 0x2B || at(1) == 0x3D ? 2 : 1;
    case 0x2D: // -
      return at(1) == 0x2D || at(1) == 0x3D ? 2 : 1;
    case 0x2A || 0x25 || 0x5E || 0x2F: // * % ^ /
      return at(1) == 0x3D ? 2 : 1;
    case 0x5B: // [ : `[]` and `[]=` are single tokens, and not brackets.
      if (at(1) == 0x5D) return at(2) == 0x3D && at(3) != 0x3D ? 3 : 2;
      return 1;
    case 0x7E: // ~
      if (at(1) == 0x2F) return at(2) == 0x3D ? 3 : 2;
      return 1;
    case 0x26: // &
      return at(1) == 0x26 || at(1) == 0x3D ? 2 : 1;
    case 0x7C: // |
      return at(1) == 0x7C || at(1) == 0x3D ? 2 : 1;
    default:
      return 1;
  }
}

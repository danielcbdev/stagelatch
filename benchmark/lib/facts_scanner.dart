/// Annotated declarations and test calls from a hand-written lexer: the
/// candidate S of ADR-0017. One lexing pass over the source, then
/// recognizers over the token list. No recursion on the input; every loop
/// advances, so the cost is linear in the source length (security S6).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:stagelatch_bench/facts_model.dart';

/// The result of the lexing pass.
final class Lexed {
  /// Creates a lexed file.
  new(this.source);

  /// The source text.
  final String source;

  /// Token start offsets.
  final starts = <int>[];

  /// Token end offsets (exclusive).
  final ends = <int>[];

  /// Token kinds, see [Kind].
  final kinds = <int>[];

  /// For an opening bracket, the index of its closing bracket; else -1.
  final match = <int>[];

  /// False when a string or block comment is unterminated, or brackets do
  /// not pair up.
  bool balanced = true;

  /// The number of tokens.
  int get length => starts.length;

  void _add(int start, int end, int kind) {
    starts.add(start);
    ends.add(end);
    kinds.add(kind);
    match.add(-1);
  }
}

/// Token kinds.
abstract final class Kind {
  /// An identifier or a keyword.
  static const word = 0;

  /// A number.
  static const number = 1;

  /// A string, or a segment of an interpolated string.
  static const string = 2;

  /// Punctuation or an operator.
  static const punct = 3;
}

bool _isLetter(int c) =>
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x41 && c <= 0x5A) ||
    c == 0x5F ||
    c == 0x24;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isHex(int c) =>
    _isDigit(c) || (c >= 0x61 && c <= 0x66) || (c >= 0x41 && c <= 0x46);

/// Lexes [s] the way the Dart scanner does, minus the keyword table.
Lexed lex(String s) {
  final out = Lexed(s);
  final n = s.length;
  var i = 0;
  if (s.startsWith('#!')) {
    while (i < n && s.codeUnitAt(i) != 0x0A) {
      i++;
    }
  }
  // Open brackets: the token index, and for `${` the string to resume
  // (the quote code, plus 0x100 when triple); 0 for the others.
  final open = <int>[];
  final resume = <int>[];

  // Pops the bracket closed by [closerCode] and returns its resume value.
  int closeBracket(int index, int closerCode) {
    if (open.isEmpty) {
      out.balanced = false;
      return 0;
    }
    final at = open.removeLast();
    final r = resume.removeLast();
    final opener = s.codeUnitAt(out.starts[at]);
    final ok = switch (closerCode) {
      0x29 => opener == 0x28,
      0x5D => opener == 0x5B,
      _ => opener == 0x7B || opener == 0x24,
    };
    if (!ok) out.balanced = false;
    out.match[at] = index;
    return r;
  }

  // Scans a string whose current segment starts at [segStart], with [from]
  // at its first content character. Returns the offset after it, negated
  // when it stopped inside a `${`.
  int string(
    int segStart,
    int from,
    int quote, {
    required bool triple,
    required bool raw,
  }) {
    var start = segStart;
    var j = from;
    while (j < n) {
      final c = s.codeUnitAt(j);
      if (c == 0x5C && !raw) {
        j += 2;
        continue;
      }
      if (c == quote) {
        if (!triple) {
          out._add(start, j + 1, Kind.string);
          return j + 1;
        }
        if (j + 2 < n &&
            s.codeUnitAt(j + 1) == quote &&
            s.codeUnitAt(j + 2) == quote) {
          out._add(start, j + 3, Kind.string);
          return j + 3;
        }
      } else if (!triple && (c == 0x0A || c == 0x0D)) {
        out
          ..balanced = false
          .._add(start, j, Kind.string);
        return j;
      } else if (c == 0x24 && !raw && j + 1 < n) {
        final next = s.codeUnitAt(j + 1);
        if (next == 0x7B) {
          out
            .._add(start, j, Kind.string)
            .._add(j, j + 2, Kind.punct);
          open.add(out.length - 1);
          resume.add(quote | (triple ? 0x100 : 0));
          return -(j + 2);
        }
        if (_isLetter(next) && next != 0x24) {
          out
            .._add(start, j, Kind.string)
            .._add(j, j + 1, Kind.punct);
          var k = j + 1;
          while (k < n) {
            final d = s.codeUnitAt(k);
            if ((_isLetter(d) && d != 0x24) || _isDigit(d)) {
              k++;
            } else {
              break;
            }
          }
          out._add(j + 1, k, Kind.word);
          start = k;
          j = k;
          continue;
        }
      }
      j++;
    }
    out
      ..balanced = false
      .._add(start, n, Kind.string);
    return n;
  }

  // A run of digits; `_` between digits is a separator.
  int digits(int from) {
    var j = from;
    while (j < n) {
      final d = s.codeUnitAt(j);
      if (_isDigit(d) ||
          (d == 0x5F && j + 1 < n && _isDigit(s.codeUnitAt(j + 1)))) {
        j++;
      } else {
        break;
      }
    }
    return j;
  }

  while (i < n) {
    final c = s.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
    } else if (c == 0x2F && i + 1 < n && s.codeUnitAt(i + 1) == 0x2F) {
      while (i < n && s.codeUnitAt(i) != 0x0A) {
        i++;
      }
    } else if (c == 0x2F && i + 1 < n && s.codeUnitAt(i + 1) == 0x2A) {
      var depth = 0;
      var closed = false;
      while (i < n) {
        if (s.codeUnitAt(i) == 0x2F &&
            i + 1 < n &&
            s.codeUnitAt(i + 1) == 0x2A) {
          depth++;
          i += 2;
        } else if (s.codeUnitAt(i) == 0x2A &&
            i + 1 < n &&
            s.codeUnitAt(i + 1) == 0x2F) {
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
    } else if (c == 0x27 || c == 0x22) {
      final triple =
          i + 2 < n && s.codeUnitAt(i + 1) == c && s.codeUnitAt(i + 2) == c;
      final r = string(i, i + (triple ? 3 : 1), c, triple: triple, raw: false);
      i = r < 0 ? -r : r;
    } else if (_isLetter(c)) {
      final start = i;
      while (i < n) {
        final d = s.codeUnitAt(i);
        if (_isLetter(d) || _isDigit(d)) {
          i++;
        } else {
          break;
        }
      }
      if (i == start + 1 &&
          c == 0x72 &&
          i < n &&
          (s.codeUnitAt(i) == 0x27 || s.codeUnitAt(i) == 0x22)) {
        final q = s.codeUnitAt(i);
        final triple =
            i + 2 < n && s.codeUnitAt(i + 1) == q && s.codeUnitAt(i + 2) == q;
        i = string(start, i + (triple ? 3 : 1), q, triple: triple, raw: true);
      } else {
        out._add(start, i, Kind.word);
      }
    } else if (_isDigit(c) ||
        (c == 0x2E && i + 1 < n && _isDigit(s.codeUnitAt(i + 1)))) {
      final start = i;
      if (c == 0x30 &&
          i + 1 < n &&
          (s.codeUnitAt(i + 1) == 0x78 || s.codeUnitAt(i + 1) == 0x58)) {
        i += 2;
        while (i < n &&
            (_isHex(s.codeUnitAt(i)) ||
                (s.codeUnitAt(i) == 0x5F &&
                    i + 1 < n &&
                    _isHex(s.codeUnitAt(i + 1))))) {
          i++;
        }
      } else {
        i = digits(i);
        if (i + 1 < n &&
            s.codeUnitAt(i) == 0x2E &&
            _isDigit(s.codeUnitAt(i + 1))) {
          i = digits(i + 1);
        }
        if (i < n && (s.codeUnitAt(i) == 0x65 || s.codeUnitAt(i) == 0x45)) {
          var j = i + 1;
          if (j < n && (s.codeUnitAt(j) == 0x2B || s.codeUnitAt(j) == 0x2D)) {
            j++;
          }
          if (j < n && _isDigit(s.codeUnitAt(j))) {
            i = digits(j);
          }
        }
      }
      out._add(start, i, Kind.number);
    } else {
      final len = _punctLength(s, i, n);
      final index = out.length;
      out._add(i, i + len, Kind.punct);
      i += len;
      if (len != 1) continue;
      switch (c) {
        case 0x28 || 0x5B || 0x7B:
          open.add(index);
          resume.add(0);
        case 0x29 || 0x5D:
          closeBracket(index, c);
        case 0x7D:
          final r = closeBracket(index, c);
          if (r != 0) {
            final next = string(
              i,
              i,
              r & 0xFF,
              triple: (r & 0x100) != 0,
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

int _punctLength(String s, int i, int n) {
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
    case 0x5B: // [  ( `[]` and `[]=` are single tokens, and not brackets)
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

/// The facts of [source], and null when the lexer found it unbalanced and
/// [requireBalanced] is set.
FactsResult? factsByScanner(
  String source, {
  Set<String> testFunctions = defaultTestFunctions,
  bool requireBalanced = false,
}) {
  final lexed = lex(source);
  if (requireBalanced && !lexed.balanced) return null;
  return _Recognizer(lexed, testFunctions).run();
}

final class _Recognizer {
  new(this.l, this.testFunctions) : s = l.source;

  final Lexed l;
  final String s;
  final Set<String> testFunctions;
  final decls = <DeclFact>[];
  List<int>? _lineStarts;

  int get n => l.length;

  bool isChar(int k, int c) =>
      k >= 0 &&
      k < n &&
      l.kinds[k] == Kind.punct &&
      l.ends[k] - l.starts[k] == 1 &&
      s.codeUnitAt(l.starts[k]) == c;

  bool isWord(int k) => k >= 0 && k < n && l.kinds[k] == Kind.word;

  bool isText(int k, String text) =>
      k >= 0 &&
      k < n &&
      l.ends[k] - l.starts[k] == text.length &&
      s.startsWith(text, l.starts[k]);

  String text(int k) => s.substring(l.starts[k], l.ends[k]);

  FactsResult run() {
    final skipLocations = <(int, int, String)>[];
    String? librarySkip;
    _topLevel(skipLocations, (v) => librarySkip ??= v);
    final calls = _calls(skipLocations, librarySkip);
    final ids = <String>{
      for (var k = 0; k < n; k++)
        if (l.kinds[k] == Kind.word) text(k),
    }.toList()..sort();
    return FactsResult(declarations: decls, calls: calls, identifiers: ids);
  }

  /// `line:column` of [offset], 1-based.
  String at(int offset) {
    final starts = _lineStarts ??= [
      0,
      for (var i = 0; i < s.length; i++)
        if (s.codeUnitAt(i) == 0x0A) i + 1,
    ];
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (starts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return '${low + 1}:${offset - starts[low] + 1}';
  }

  /// Reads annotations from [from]; returns the index after them, adding the
  /// names (as written) to [names] and the start of each to [offsets].
  int annotations(int from, List<String> names, List<int> offsets) {
    var k = from;
    while (isChar(k, 0x40)) {
      offsets.add(l.starts[k]);
      var j = k + 1;
      final buf = StringBuffer();
      if (isWord(j)) {
        buf.write(text(j));
        j++;
      }
      while (isChar(j, 0x2E) && isWord(j + 1)) {
        buf.write('.${text(j + 1)}');
        j += 2;
      }
      if (isChar(j, 0x3C)) {
        var depth = 0;
        while (j < n) {
          if (isChar(j, 0x3C)) depth++;
          if (isChar(j, 0x3E)) depth--;
          if (isText(j, '>>')) depth -= 2;
          j++;
          if (depth <= 0) break;
        }
      }
      if (isChar(j, 0x28) && l.match[j] > 0) j = l.match[j] + 1;
      names.add(buf.toString());
      k = j;
    }
    return k;
  }

  void _topLevel(List<(int, int, String)> skips, void Function(String) lib) {
    var k = 0;
    while (k < n) {
      if (isChar(k, 0x3B)) {
        k++;
        continue;
      }
      final names = <String>[];
      final offsets = <int>[];
      final a = annotations(k, names, offsets);
      if (a >= n) return;
      final end = declEnd(a, n);
      final directive =
          isText(a, 'library') ||
          isText(a, 'import') ||
          isText(a, 'export') ||
          isText(a, 'part');
      if (directive) {
        if (isText(a, 'library')) {
          for (var i = 0; i < names.length; i++) {
            if (names[i] == 'Skip') lib(at(offsets[i]));
          }
        }
      } else {
        for (var i = 0; i < names.length; i++) {
          if (names[i] == 'Skip') skips.add((a, end, at(offsets[i])));
        }
        final info = header(a, end, owner: null);
        if (info != null) {
          record(k, end, names, offsets, info.name);
          if (info.bodyOpen >= 0) {
            members(info.name, info.bodyOpen, isEnum: info.isEnum);
          }
        }
      }
      k = end + 1;
    }
  }

  /// Annotated members of the class-like body opened at [open].
  void members(String owner, int open, {required bool isEnum}) {
    final close = l.match[open] < 0 ? n : l.match[open];
    var k = open + 1;
    if (isEnum) {
      // Constants, up to a `;` at depth 0 or the end of the body.
      while (k < close) {
        final names = <String>[];
        final offsets = <int>[];
        final a = annotations(k, names, offsets);
        if (a >= close) return;
        if (isChar(a, 0x3B)) {
          k = a + 1;
          break;
        }
        var j = a + 1;
        if (isChar(j, 0x3C)) {
          var depth = 0;
          while (j < close) {
            if (isChar(j, 0x3C)) depth++;
            if (isChar(j, 0x3E)) depth--;
            if (isText(j, '>>')) depth -= 2;
            j++;
            if (depth <= 0) break;
          }
        }
        if (isChar(j, 0x2E)) j += 2;
        if (isChar(j, 0x28) && l.match[j] > 0) j = l.match[j] + 1;
        if (isChar(j, 0x7B) && l.match[j] > 0) j = l.match[j] + 1;
        record(k, j - 1, names, offsets, '$owner.${text(a)}');
        if (isChar(j, 0x2C)) j++;
        k = j;
      }
    }
    while (k < close) {
      if (isChar(k, 0x3B)) {
        k++;
        continue;
      }
      final names = <String>[];
      final offsets = <int>[];
      final a = annotations(k, names, offsets);
      if (a >= close) return;
      final end = declEnd(a, close);
      final info = header(a, end, owner: owner);
      if (info != null) record(k, end, names, offsets, info.name);
      k = end + 1;
    }
  }

  void record(
    int first,
    int end,
    List<String> names,
    List<int> offsets,
    String name,
  ) {
    final relevant = [
      for (final a in names)
        if (!ignoredAnnotations.contains(a)) a,
    ]..sort();
    if (relevant.isEmpty) return;
    final last = end >= n ? n - 1 : end;
    final lexemes = [for (var k = first; k <= last; k++) text(k)];
    final pos = at(offsets.first).split(':');
    decls.add(
      DeclFact(
        name: name,
        annotations: relevant,
        tokenHash: crypto.sha256
            .convert(utf8.encode(lexemes.join(' ')))
            .toString(),
        line: int.parse(pos[0]),
        column: int.parse(pos[1]),
      ),
    );
  }

  /// The index of the last token of the declaration starting at [a]: the
  /// `;`, or the `}` of its body.
  int declEnd(int a, int limit) {
    var k = a;
    var sawEq = false;
    var sawColon = false;
    while (k < limit) {
      if (isChar(k, 0x3B)) return k;
      if (isChar(k, 0x28) || isChar(k, 0x5B)) {
        k = l.match[k] < 0 ? limit : l.match[k] + 1;
        continue;
      }
      if (isChar(k, 0x7B)) {
        final close = l.match[k] < 0 ? limit - 1 : l.match[k];
        final prev = k - 1;
        final expression =
            sawEq ||
            (sawColon &&
                !(isChar(prev, 0x29) ||
                    isChar(prev, 0x7D) ||
                    (isWord(prev) &&
                        !isText(prev, 'const') &&
                        !isText(prev, 'new'))));
        if (!expression) return close;
        k = close + 1;
        continue;
      }
      if (l.kinds[k] == Kind.punct) {
        if (isChar(k, 0x3D) || isText(k, '=>')) {
          if (!sawColon) sawEq = true;
        } else if (isChar(k, 0x3A)) {
          sawColon = true;
        }
      }
      k++;
    }
    return limit - 1;
  }

  /// The name of the declaration at [a]..[end], and where its body opens,
  /// or null when it is not a kind that can be named.
  _Header? header(int a, int end, {required String? owner}) {
    // Header tokens: up to the first `(`, `{`, `;`, `=`, `=>`, or a `,`, at
    // angle depth 0.
    var k = a;
    var angle = 0;
    var stop = -1;
    var classLike = -1;
    while (k <= end && k < n) {
      if (angle == 0 && l.kinds[k] == Kind.word) {
        if (classLike < 0 &&
            (isText(k, 'class') ||
                isText(k, 'mixin') ||
                isText(k, 'enum') ||
                isText(k, 'extension') ||
                isText(k, 'typedef'))) {
          classLike = k;
        }
      }
      if (l.kinds[k] == Kind.punct) {
        if (isChar(k, 0x3C)) {
          angle++;
        } else if (isChar(k, 0x3E)) {
          if (angle > 0) angle--;
        } else if (isText(k, '>>')) {
          angle = angle >= 2 ? angle - 2 : 0;
        } else if (angle == 0 &&
            (isChar(k, 0x28) ||
                isChar(k, 0x7B) ||
                isChar(k, 0x3B) ||
                isChar(k, 0x3D) ||
                isText(k, '=>') ||
                isChar(k, 0x2C))) {
          stop = k;
          break;
        }
      }
      k++;
    }
    if (classLike >= 0 && owner == null) {
      final kw = text(classLike);
      var j = classLike;
      String? name;
      if (kw == 'mixin' && isText(j + 1, 'class')) j++;
      if (kw == 'extension') {
        if (isText(j + 1, 'type') && isWord(j + 2)) {
          name = text(j + 2);
        } else if (isWord(j + 1) && !isText(j + 1, 'on')) {
          name = text(j + 1);
        } else {
          name = '<unnamed>';
        }
      } else if (kw == 'typedef') {
        if (isWord(j + 1) && (isChar(j + 2, 0x3D) || isChar(j + 2, 0x3C))) {
          name = text(j + 1);
        } else {
          // Old style: `typedef R Name(args);`
          var p = j + 1;
          while (p <= end && !isChar(p, 0x28)) {
            p++;
          }
          name = isWord(p - 1) ? text(p - 1) : null;
        }
      } else if (isWord(j + 1)) {
        name = text(j + 1);
      }
      if (name == null) return null;
      var open = -1;
      for (var p = classLike; p <= end; p++) {
        if (isChar(p, 0x28) && l.match[p] > 0) {
          p = l.match[p];
          continue;
        }
        if (isChar(p, 0x7B)) {
          open = p;
          break;
        }
        if (isChar(p, 0x3B) || isChar(p, 0x3D)) break;
      }
      return _Header(name, open, isEnum: kw == 'enum');
    }
    if (stop < 0) return null;
    if (isChar(stop, 0x28)) {
      // Function, method or constructor. Skip type parameters: `name<T>(`.
      var nameTok = stop - 1;
      if (isChar(nameTok, 0x3E) || isText(nameTok, '>>')) {
        var depth = 0;
        while (nameTok >= a) {
          if (isChar(nameTok, 0x3E)) depth++;
          if (isText(nameTok, '>>')) depth += 2;
          if (isChar(nameTok, 0x3C)) depth--;
          nameTok--;
          if (depth <= 0) break;
        }
      }
      if (nameTok < a) return null;
      if (owner != null) {
        // `Owner`, `Owner.named`, `factory Owner.named`, operators.
        if (isWord(nameTok) &&
            isChar(nameTok - 1, 0x2E) &&
            isText(nameTok - 2, owner)) {
          return _Header('$owner.${text(nameTok)}', -1);
        }
        if (isText(nameTok, owner)) return _Header('$owner.new', -1);
        if (isText(nameTok - 1, 'operator')) {
          return _Header('$owner.${text(nameTok)}', -1);
        }
        if (!isWord(nameTok)) {
          var p = nameTok;
          while (p > a && !isText(p, 'operator')) {
            p--;
          }
          if (isText(p, 'operator')) {
            return _Header('$owner.${text(p + 1)}', -1);
          }
          return null;
        }
        return _Header('$owner.${text(nameTok)}', -1);
      }
      if (!isWord(nameTok)) return null;
      return _Header(text(nameTok), -1);
    }
    // Variable, field, getter: the last word before the stop.
    var p = stop - 1;
    while (p >= a && !isWord(p)) {
      p--;
    }
    if (p < a) return null;
    final name = text(p);
    return _Header(owner == null ? name : '$owner.$name', -1);
  }

  List<CallFact> _calls(List<(int, int, String)> skips, String? librarySkip) {
    final out = <CallFact>[];
    final groups = <(int, String)>[];
    for (var k = 0; k < n; k++) {
      while (groups.isNotEmpty && k > groups.last.$1) {
        groups.removeLast();
      }
      if (l.kinds[k] != Kind.word || !isChar(k + 1, 0x28)) continue;
      final name = text(k);
      if (!testFunctions.contains(name) || !_callPosition(k)) continue;
      final open = k + 1;
      final close = l.match[open];
      if (close < 0) continue;
      // Split the arguments at commas of depth 0.
      final args = <(int, int)>[];
      var start = open + 1;
      var j = open + 1;
      while (j < close) {
        if (isChar(j, 0x28) || isChar(j, 0x5B) || isChar(j, 0x7B)) {
          j = l.match[j] < 0 ? close : l.match[j] + 1;
          continue;
        }
        if (isText(j, r'${')) {
          j = l.match[j] < 0 ? close : l.match[j] + 1;
          continue;
        }
        if (isChar(j, 0x2C)) {
          if (j > start) args.add((start, j));
          start = j + 1;
        }
        j++;
      }
      if (close > start) args.add((start, close));
      (int, int)? first;
      String? solo;
      String? skip;
      for (final (a, b) in args) {
        final named = isWord(a) && isChar(a + 1, 0x3A);
        if (!named) {
          first ??= (a, b);
          continue;
        }
        final label = text(a);
        final valueStart = a + 2;
        final single = b - valueStart == 1;
        final isFalse = single && isText(valueStart, 'false');
        final isNull = single && isText(valueStart, 'null');
        if (label == 'solo' && !isFalse) solo ??= at(l.starts[a]);
        if (label == 'skip' && !isFalse && !isNull) skip ??= at(l.starts[a]);
      }
      if (first == null) continue;
      final description = _description(first.$1, first.$2);
      String? functionSkip;
      for (final (from, to, location) in skips) {
        if (k >= from && k <= to) functionSkip = location;
      }
      final pos = at(l.starts[k]).split(':');
      out.add(
        CallFact(
          function: name,
          description: description,
          groups: [for (final (_, d) in groups) d],
          line: int.parse(pos[0]),
          column: int.parse(pos[1]),
          solo: solo,
          skip: skip ?? functionSkip ?? librarySkip,
        ),
      );
      if (name == groupFunction) groups.add((close, description));
    }
    return out;
  }

  bool _callPosition(int k) {
    if (k == 0) return true;
    final p = k - 1;
    if (l.kinds[p] == Kind.punct) {
      return switch (text(p)) {
        ';' || '{' || '}' || '(' || ',' || '=>' || '=' || ':' || '[' => true,
        '?' || '!' || '&&' || '||' || '??' || '==' || '!=' => true,
        _ => false,
      };
    }
    if (l.kinds[p] == Kind.word) {
      return switch (text(p)) {
        'await' || 'return' || 'yield' || 'throw' || 'else' || 'do' => true,
        _ => false,
      };
    }
    return false;
  }

  /// The literal's value when [a]..[b] is only plain string literals, the
  /// source text otherwise. An interpolated string has `$` tokens between
  /// its segments, so a run of only string tokens is plain literals.
  String _description(int a, int b) {
    var allStrings = true;
    for (var k = a; k < b; k++) {
      if (l.kinds[k] != Kind.string) {
        allStrings = false;
        break;
      }
    }
    if (allStrings) {
      final buf = StringBuffer();
      for (var k = a; k < b; k++) {
        buf.write(_decode(text(k)));
      }
      return buf.toString();
    }
    return s.substring(l.starts[a], l.ends[b - 1]);
  }
}

final class _Header {
  const new(this.name, this.bodyOpen, {this.isEnum = false});

  final String name;
  final int bodyOpen;
  final bool isEnum;
}

/// The value of one string token.
String _decode(String lexeme) {
  var i = 0;
  var raw = false;
  if (lexeme.startsWith('r')) {
    raw = true;
    i = 1;
  }
  final quote = lexeme[i];
  final triple = lexeme.startsWith(quote * 3, i) && lexeme.length >= i + 6;
  final from = i + (triple ? 3 : 1);
  var to = lexeme.length - (triple ? 3 : 1);
  if (to < from) to = from;
  var body = lexeme.substring(from, to);
  if (triple) {
    if (body.startsWith('\r\n')) {
      body = body.substring(2);
    } else if (body.startsWith('\n') || body.startsWith('\r')) {
      body = body.substring(1);
    }
  }
  if (raw || !body.contains(r'\')) return body;
  final out = StringBuffer();
  for (var j = 0; j < body.length; j++) {
    final c = body[j];
    if (c != r'\' || j + 1 >= body.length) {
      out.write(c);
      continue;
    }
    j++;
    final e = body[j];
    switch (e) {
      case 'n':
        out.write('\n');
      case 'r':
        out.write('\r');
      case 't':
        out.write('\t');
      case 'b':
        out.write('\b');
      case 'f':
        out.write('\f');
      case 'v':
        out.write('\v');
      case 'x':
        final hex = body.substring(j + 1, (j + 3).clamp(0, body.length));
        out.writeCharCode(int.tryParse(hex, radix: 16) ?? 0);
        j += 2;
      case 'u':
        if (j + 1 < body.length && body[j + 1] == '{') {
          final close = body.indexOf('}', j);
          final hex = body.substring(j + 2, close < 0 ? body.length : close);
          out.writeCharCode(int.tryParse(hex, radix: 16) ?? 0);
          j = close < 0 ? body.length : close;
        } else {
          final hex = body.substring(j + 1, (j + 5).clamp(0, body.length));
          out.writeCharCode(int.tryParse(hex, radix: 16) ?? 0);
          j += 4;
        }
      case '\n' || '\r':
        if (e == '\r' && j + 1 < body.length && body[j + 1] == '\n') j++;
      default:
        out.write(e);
    }
  }
  return out.toString();
}

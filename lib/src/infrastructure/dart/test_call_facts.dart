/// Calls to test functions from the tokens of a file (ADR-0017,
/// docs/specs/dart-toolchain.md, section 6).
library;

import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/dart_lexer.dart';
import 'package:stagelatch/src/infrastructure/dart/declaration_facts.dart';
import 'package:stagelatch/src/infrastructure/dart/line_index.dart';

/// The function whose calls open a group.
const _groupFunction = 'group';

/// How many enclosing groups a call remembers: the outermost ones. A real
/// suite is a few levels deep; the cap keeps a hostile file, with thousands
/// of nested groups, from making every call copy thousands of strings.
const _maxTrackedGroups = 64;

/// How many characters of a description's source text are kept, for the
/// same reason: a call whose first argument is huge, inside calls that are
/// huge, must not cost the square of the file.
const _maxSourceDescription = 4096;

const _openParen = 0x28;
const _openBracket = 0x5B;
const _openBrace = 0x7B;
const _comma = 0x2C;
const _colon = 0x3A;

/// The calls to [functions] in the file, in source order.
///
/// A call is unqualified (`test(...)`, not `obj.test(...)` or a cascade),
/// has at least one positional argument, and is found by the token before
/// the name: a statement or expression boundary, or `await`, `return`,
/// `yield`, `throw`, `else` or `do`. That keeps `void test(...)` from being
/// a call. The first positional argument is the description: a string
/// literal's value, or its source text when it is anything else.
///
/// A `group` call is itself a call, and the calls inside it list its
/// description in [TestCall.groups]. A `skip:` argument other than `false`
/// and `null` skips the call; so does a `@Skip` annotation on the enclosing
/// top-level function or on the library ([scan]). A `solo:` argument other
/// than `false` marks it solo.
///
/// [lexed] must be balanced. The cost is linear in the file.
List<TestCall> extractTestCalls(
  Lexed lexed,
  RepoPath path,
  Set<String> functions,
  DeclarationScan scan,
  LineIndex lines,
) {
  if (functions.isEmpty) return const [];
  return _Extractor(lexed, path, functions, scan, lines).extract();
}

final class _Extractor {
  new(this._lexed, this._path, this._functions, this._scan, this._lines)
    : _s = _lexed.source;

  final Lexed _lexed;
  final RepoPath _path;
  final Set<String> _functions;
  final DeclarationScan _scan;
  final LineIndex _lines;
  final String _s;

  int get _n => _lexed.length;

  bool _isChar(int k, int c) =>
      k >= 0 &&
      k < _n &&
      _lexed.kinds[k] == TokenKind.punctuation &&
      _lexed.ends[k] - _lexed.starts[k] == 1 &&
      _s.codeUnitAt(_lexed.starts[k]) == c;

  bool _isWord(int k) => k >= 0 && k < _n && _lexed.kinds[k] == TokenKind.word;

  bool _isText(int k, String text) =>
      k >= 0 &&
      k < _n &&
      _lexed.ends[k] - _lexed.starts[k] == text.length &&
      _s.startsWith(text, _lexed.starts[k]);

  String _text(int k) => _lexed.lexeme(k);

  Location _location(int startToken, int endToken) => Location(
    _path,
    _lines.positionOf(_lexed.starts[startToken]),
    _lines.positionOf(_lexed.ends[endToken]),
  );

  List<TestCall> extract() {
    final calls = <TestCall>[];
    // Enclosing groups: the token index of each one's closing parenthesis,
    // and its description.
    final groups = <(int, String)>[];
    for (var k = 0; k < _n; k++) {
      while (groups.isNotEmpty && k > groups.last.$1) {
        groups.removeLast();
      }
      if (_lexed.kinds[k] != TokenKind.word || !_isChar(k + 1, _openParen)) {
        continue;
      }
      final name = _text(k);
      if (!_functions.contains(name) || !_isCallPosition(k)) continue;
      final open = k + 1;
      final close = _lexed.closerOf(open);
      if (close < 0) continue;

      // Split the arguments at the commas of depth 0.
      final arguments = <(int, int)>[];
      var start = open + 1;
      var j = open + 1;
      while (j < close) {
        if (_isChar(j, _openParen) ||
            _isChar(j, _openBracket) ||
            _isChar(j, _openBrace) ||
            _isText(j, r'${')) {
          j = _lexed.closerOf(j) < 0 ? close : _lexed.closerOf(j) + 1;
          continue;
        }
        if (_isChar(j, _comma)) {
          if (j > start) arguments.add((start, j));
          start = j + 1;
        }
        j++;
      }
      if (close > start) arguments.add((start, close));

      (int, int)? first;
      Location? solo;
      Location? skip;
      for (final (a, b) in arguments) {
        final isNamed = _isWord(a) && _isChar(a + 1, _colon);
        if (!isNamed) {
          first ??= (a, b);
          continue;
        }
        final label = _text(a);
        final single = b - (a + 2) == 1;
        final isFalse = single && _isText(a + 2, 'false');
        final isNull = single && _isText(a + 2, 'null');
        if (label == 'solo' && !isFalse) solo ??= _location(a, b - 1);
        if (label == 'skip' && !isFalse && !isNull) {
          skip ??= _location(a, b - 1);
        }
      }
      if (first == null) continue;

      final description = _description(first.$1, first.$2);
      calls.add(
        TestCall(
          function: name,
          description: description,
          groups: [for (final (_, d) in groups.take(_maxTrackedGroups)) d],
          location: _location(k, close),
          solo: solo,
          skip: skip ?? _enclosingSkip(k) ?? _scan.librarySkip,
        ),
      );
      if (name == _groupFunction) groups.add((close, description));
    }
    return calls;
  }

  /// The `@Skip` annotation of the top-level declaration that holds token
  /// [k], by binary search: scopes are sorted and do not overlap.
  Location? _enclosingSkip(int k) {
    final scopes = _scan.skipScopes;
    var low = 0;
    var high = scopes.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final scope = scopes[mid];
      if (k < scope.from) {
        high = mid - 1;
      } else if (k > scope.to) {
        low = mid + 1;
      } else {
        return scope.location;
      }
    }
    return null;
  }

  /// Whether the token before the name at [k] lets it start a call.
  bool _isCallPosition(int k) {
    if (k == 0) return true;
    final previous = k - 1;
    if (_lexed.kinds[previous] == TokenKind.punctuation) {
      return switch (_text(previous)) {
        ';' || '{' || '}' || '(' || ',' || '=>' || '=' || ':' || '[' => true,
        '?' || '!' || '&&' || '||' || '??' || '==' || '!=' => true,
        _ => false,
      };
    }
    if (_lexed.kinds[previous] == TokenKind.word) {
      return switch (_text(previous)) {
        'await' || 'return' || 'yield' || 'throw' || 'else' || 'do' => true,
        _ => false,
      };
    }
    return false;
  }

  /// The value of the string literal [a]..[b], or the (capped) source text
  /// of the argument when it is not one. An interpolated string has `$`
  /// tokens between its segments, so a run of only string tokens is plain
  /// literals.
  String _description(int a, int b) {
    var onlyStrings = true;
    for (var k = a; k < b; k++) {
      if (_lexed.kinds[k] != TokenKind.string) {
        onlyStrings = false;
        break;
      }
    }
    if (onlyStrings) {
      final buffer = StringBuffer();
      for (var k = a; k < b; k++) {
        buffer.write(_decode(_text(k)));
      }
      return buffer.toString();
    }
    final start = _lexed.starts[a];
    final end = _lexed.ends[b - 1];
    return _s.substring(
      start,
      end - start > _maxSourceDescription ? start + _maxSourceDescription : end,
    );
  }
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
    // A newline right after the opening quotes is not part of the value.
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
    final escape = body[j];
    switch (escape) {
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
          final end = body.indexOf('}', j);
          final hex = body.substring(j + 2, end < 0 ? body.length : end);
          out.writeCharCode(int.tryParse(hex, radix: 16) ?? 0);
          j = end < 0 ? body.length : end;
        } else {
          final hex = body.substring(j + 1, (j + 5).clamp(0, body.length));
          out.writeCharCode(int.tryParse(hex, radix: 16) ?? 0);
          j += 4;
        }
      case '\n' || '\r':
        // A line continuation: the backslash and the line break vanish.
        if (escape == '\r' && j + 1 < body.length && body[j + 1] == '\n') j++;
      default:
        out.write(escape);
    }
  }
  return out.toString();
}

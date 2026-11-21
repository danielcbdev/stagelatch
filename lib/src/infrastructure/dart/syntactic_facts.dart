/// Syntactic facts without a parser (ADR-0008, ADR-0013,
/// docs/specs/dart-toolchain.md, section 6).
library;

import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/dart_lexer.dart';
import 'package:stagelatch/src/infrastructure/dart/declaration_facts.dart';
import 'package:stagelatch/src/infrastructure/dart/line_index.dart';
import 'package:stagelatch/src/infrastructure/dart/test_call_facts.dart';

/// Extracts the facts of one Dart file with hand-written scanners, without a
/// parser (ADR-0017).
///
/// Directives come from a scanner that reads from the top of the file and
/// stops at the first token that does not start a directive, so a broken
/// file yields the directives before the point where it stops. The spike
/// measured it at about 170 times the speed of `parseString`, with the same
/// directives on every file of a 2,462-file app.
///
/// Annotated declarations come from a lexer over the whole file
/// (`dart_lexer.dart`) and the recognizers of `declaration_facts.dart`. When
/// the lexer finds an unterminated string or block comment, or brackets
/// that do not pair, the file is not well formed and has no declarations:
/// what a recognizer would say about it means nothing, and `analyze` reports
/// the error.
///
/// It never throws, and every loop advances through the source, so the cost
/// is linear in its length (security S6).
final class SyntacticFacts {
  /// Creates the extractor. [testFunctions] are the functions whose calls
  /// become `testCalls` (`tests.functions` of the configuration).
  const new({this.testFunctions = defaultTestFunctions});

  /// The functions `testCalls` are collected for.
  final Set<String> testFunctions;

  /// The facts of [source], the content of [path].
  DartFileFacts extract(String source, RepoPath path) {
    final directives = _Scanner(source, path).directives();
    final lexed = lex(source);
    if (!lexed.balanced) {
      return DartFileFacts(directives: directives, isWellFormed: false);
    }
    final lines = LineIndex(source);
    final scan = scanDeclarations(lexed, path, lines);
    return DartFileFacts(
      directives: directives,
      annotatedDeclarations: scan.declarations,
      testCalls: extractTestCalls(lexed, path, testFunctions, scan, lines),
    );
  }
}

/// The functions inspected when `tests.functions` is not configured
/// (docs/specs/config.md, section 3).
const Set<String> defaultTestFunctions = {'test', 'testWidgets', 'group'};

final class _Scanner {
  new(this._s, this._path);

  final String _s;
  final RepoPath _path;
  var _i = 0;
  List<int>? _lineStarts;

  bool get _done => _i >= _s.length;
  int get _c => _s.codeUnitAt(_i);

  List<Directive> directives() {
    final directives = <Directive>[];
    if (_s.startsWith('﻿')) _i++;
    if (_s.startsWith('#!', _i)) _skipLine();
    while (true) {
      _skipTrivia();
      if (_done) return directives;
      if (_c == 0x40 /* @ */ ) {
        _skipAnnotation();
        continue;
      }
      final word = _identifier();
      switch (word) {
        case 'library':
          _readDirective(null, directives);
        case 'import':
          _readDirective(DirectiveKind.import, directives);
        case 'export':
          _readDirective(DirectiveKind.export, directives);
        case 'part':
          _skipTrivia();
          final save = _i;
          if (_identifier() == 'of') {
            _readDirective(DirectiveKind.partOf, directives);
          } else {
            _i = save;
            _readDirective(DirectiveKind.part, directives);
          }
        default:
          return directives;
      }
    }
  }

  /// Reads up to the `;` that ends a directive. String literals outside
  /// parentheses are URIs, one directive each (a conditional import has
  /// one per branch); adjacent literals form one URI. With a null [kind]
  /// the directive is skipped.
  void _readDirective(DirectiveKind? kind, List<Directive> out) {
    var depth = 0;
    int? uriStart;
    var uri = StringBuffer();
    void flush(int end) {
      if (uriStart != null && kind != null) {
        out.add(
          Directive(
            kind: kind,
            uri: uri.toString(),
            location: Location(_path, _position(uriStart!), _position(end)),
          ),
        );
      }
      uriStart = null;
      uri = StringBuffer();
    }

    var lastStringEnd = 0;
    while (!_done) {
      _skipTrivia();
      if (_done) break;
      final c = _c;
      if (_startsString()) {
        final start = _i;
        final value = _string();
        if (depth == 0) {
          uriStart ??= start;
          uri.write(value);
          lastStringEnd = _i;
        }
        continue;
      }
      if (uriStart != null) flush(lastStringEnd);
      if (c == 0x3B /* ; */ && depth == 0) {
        _i++;
        return;
      }
      if (c == 0x28 /* ( */ ) depth++;
      if (c == 0x29 /* ) */ && depth > 0) depth--;
      _i++;
    }
    flush(lastStringEnd);
  }

  bool _startsString() {
    final c = _c;
    if (c == 0x27 || c == 0x22) return true;
    if ((c == 0x72 || c == 0x52) && _i + 1 < _s.length) {
      final n = _s.codeUnitAt(_i + 1);
      // r'...' or r"...", and not the end of an identifier like `bar'`.
      final atWordStart = _i == 0 || !_isIdentifierPart(_s.codeUnitAt(_i - 1));
      return atWordStart && (n == 0x27 || n == 0x22);
    }
    return false;
  }

  /// Reads a string literal and returns its content. Escapes are skipped,
  /// not decoded; URIs do not use them. An unterminated literal ends at the
  /// end of the source.
  String _string() {
    final raw = _c == 0x72 || _c == 0x52;
    if (raw) _i++;
    final quote = _s[_i];
    final triple = _s.startsWith(quote * 3, _i);
    final close = triple ? quote * 3 : quote;
    _i += close.length;
    final start = _i;
    while (!_done) {
      if (!raw && _c == 0x5C /* \ */ ) {
        _i += 2;
        continue;
      }
      if (_s.startsWith(close, _i)) {
        final value = _s.substring(start, _i);
        _i += close.length;
        return value;
      }
      if (!triple && (_c == 0x0A || _c == 0x0D)) break;
      _i++;
    }
    if (_i > _s.length) _i = _s.length;
    return _s.substring(start, _i);
  }

  void _skipAnnotation() {
    _i++; // @
    _identifier();
    while (!_done && _c == 0x2E /* . */ ) {
      _i++;
      _identifier();
    }
    _skipTrivia();
    if (_done || _c != 0x28 /* ( */ ) return;
    var depth = 0;
    while (!_done) {
      if (_startsString()) {
        _string();
        continue;
      }
      if (_c == 0x28) depth++;
      if (_c == 0x29) {
        depth--;
        if (depth == 0) {
          _i++;
          return;
        }
      }
      _i++;
    }
  }

  String _identifier() {
    final start = _i;
    while (!_done && _isIdentifierPart(_c)) {
      _i++;
    }
    return _s.substring(start, _i);
  }

  static bool _isIdentifierPart(int c) =>
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x5F ||
      c == 0x24;

  void _skipTrivia() {
    while (!_done) {
      final c = _c;
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0xFEFF) {
        _i++;
      } else if (_s.startsWith('//', _i)) {
        _skipLine();
      } else if (_s.startsWith('/*', _i)) {
        _skipBlockComment();
      } else {
        return;
      }
    }
  }

  void _skipLine() {
    final end = _s.indexOf('\n', _i);
    _i = end < 0 ? _s.length : end + 1;
  }

  /// Dart block comments nest.
  void _skipBlockComment() {
    var depth = 0;
    while (!_done) {
      if (_s.startsWith('/*', _i)) {
        depth++;
        _i += 2;
      } else if (_s.startsWith('*/', _i)) {
        depth--;
        _i += 2;
        if (depth == 0) return;
      } else {
        _i++;
      }
    }
  }

  /// The 1-based line and column of [offset]. A line ends at `\n`; a `\r`
  /// before it belongs to the line.
  Position _position(int offset) {
    final starts = _lineStarts ??= [
      0,
      for (var i = 0; i < _s.length; i++)
        if (_s.codeUnitAt(i) == 0x0A) i + 1,
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
    return Position(low + 1, offset - starts[low] + 1);
  }
}

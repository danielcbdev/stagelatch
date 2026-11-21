/// Annotated declarations from the tokens of a file (ADR-0017,
/// docs/specs/dart-toolchain.md, section 6).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/dart_lexer.dart';
import 'package:stagelatch/src/infrastructure/dart/line_index.dart';

/// Annotation names that never make a declaration "annotated".
const _ignoredAnnotations = {
  'override',
  'protected',
  'visibleForTesting',
  'immutable',
  'Deprecated',
  'deprecated',
};

const _openParen = 0x28;
const _closeAngle = 0x3E;
const _openAngle = 0x3C;
const _openBrace = 0x7B;
const _semicolon = 0x3B;
const _equals = 0x3D;
const _comma = 0x2C;
const _colon = 0x3A;
const _dot = 0x2E;
const _at = 0x40;
const _openBracket = 0x5B;

/// A top-level declaration that carries a `@Skip` annotation: the tokens it
/// covers, and where the annotation is.
typedef SkipScope = ({int from, int to, Location location});

/// What reading the declarations of a file found.
final class DeclarationScan {
  /// Creates the result.
  const new({
    required this.declarations,
    required this.skipScopes,
    required this.librarySkip,
  });

  /// The annotated declarations, in source order.
  final List<AnnotatedDeclaration> declarations;

  /// Top-level declarations with a `@Skip` annotation, in token order. They
  /// do not overlap, so a token is inside at most one.
  final List<SkipScope> skipScopes;

  /// The `@Skip` annotation of the `library` directive, or null.
  final Location? librarySkip;
}

/// The annotated declarations of a file, in source order: top-level
/// declarations, and the members and enum constants of class-like ones. It
/// also finds the `@Skip` annotations that skip whole tests.
///
/// There is no parser here, so where a declaration ends is decided from the
/// tokens: at the first `;`, or at the `}` that closes its body. After a
/// depth-0 `=` or `=>` a `{` is an expression, and after the `:` of a
/// constructor's initializer list it is one unless the token before it is
/// `)`, `}` or a word other than `const` and `new`. The cases this gets
/// wrong are listed in `docs/spike/facts-report.md`.
///
/// [lexed] must be balanced; with brackets that do not pair the ends of
/// declarations mean nothing, and the caller does not ask.
DeclarationScan scanDeclarations(Lexed lexed, RepoPath path, LineIndex lines) {
  final recognizer = _Recognizer(lexed, path, lines)..topLevel();
  return DeclarationScan(
    declarations: recognizer.declarations,
    skipScopes: recognizer.skipScopes,
    librarySkip: recognizer.librarySkip,
  );
}

/// The result of reading a declaration's header: its name, and where its
/// body opens when it has one.
final class _Header {
  const new(this.name, this.bodyOpen, {this.isEnum = false});

  final String name;
  final int bodyOpen;
  final bool isEnum;
}

/// One annotation: its name as written, and the offsets it covers.
typedef _Annotation = ({String name, int start, int end});

final class _Recognizer {
  new(this._lexed, this._path, this._lines) : _s = _lexed.source;

  final Lexed _lexed;
  final RepoPath _path;
  final LineIndex _lines;
  final String _s;
  final declarations = <AnnotatedDeclaration>[];
  final skipScopes = <SkipScope>[];
  Location? librarySkip;

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

  Location _location(int start, int end) =>
      Location(_path, _lines.positionOf(start), _lines.positionOf(end));

  /// Reads annotations from [from], adding each to [annotations] in order;
  /// returns the index after them.
  int _annotations(int from, List<_Annotation> annotations) {
    var k = from;
    while (_isChar(k, _at)) {
      final start = _lexed.starts[k];
      var j = k + 1;
      final buffer = StringBuffer();
      if (_isWord(j)) {
        buffer.write(_text(j));
        j++;
      }
      while (_isChar(j, _dot) && _isWord(j + 1)) {
        buffer.write('.${_text(j + 1)}');
        j += 2;
      }
      if (_isChar(j, _openAngle)) {
        j = _afterAngles(j, _n);
      }
      if (_isChar(j, _openParen) && _lexed.closerOf(j) > 0) {
        j = _lexed.closerOf(j) + 1;
      }
      annotations.add((
        name: buffer.toString(),
        start: start,
        end: _lexed.ends[j - 1],
      ));
      k = j;
    }
    return k;
  }

  /// The index after the angle brackets that open at [open]: type
  /// arguments, which the lexer does not pair.
  int _afterAngles(int open, int limit) {
    var depth = 0;
    var j = open;
    while (j < limit) {
      if (_isChar(j, _openAngle)) depth++;
      if (_isChar(j, _closeAngle)) depth--;
      if (_isText(j, '>>')) depth -= 2;
      j++;
      if (depth <= 0) break;
    }
    return j;
  }

  void topLevel() {
    var k = 0;
    while (k < _n) {
      if (_isChar(k, _semicolon)) {
        k++;
        continue;
      }
      final annotations = <_Annotation>[];
      final a = _annotations(k, annotations);
      if (a >= _n) return;
      final end = _declarationEnd(a, _n);
      if (_isText(a, 'library')) {
        for (final annotation in annotations) {
          if (annotation.name == 'Skip') {
            librarySkip ??= _location(annotation.start, annotation.end);
          }
        }
      } else if (!_isText(a, 'import') &&
          !_isText(a, 'export') &&
          !_isText(a, 'part')) {
        for (final annotation in annotations) {
          if (annotation.name == 'Skip') {
            skipScopes.add((
              from: a,
              to: end,
              location: _location(annotation.start, annotation.end),
            ));
            break;
          }
        }
        final header = _header(a, end, owner: null);
        if (header != null) {
          _record(k, end, annotations, header.name);
          if (header.bodyOpen >= 0) {
            _members(header.name, header.bodyOpen, isEnum: header.isEnum);
          }
        }
      }
      k = end + 1;
    }
  }

  /// Annotated members of the class-like body opened at [open].
  void _members(String owner, int open, {required bool isEnum}) {
    final close = _lexed.closerOf(open) < 0 ? _n : _lexed.closerOf(open);
    var k = open + 1;
    if (isEnum) {
      // Constants, up to a `;` at depth 0 or the end of the body.
      while (k < close) {
        final annotations = <_Annotation>[];
        final a = _annotations(k, annotations);
        if (a >= close) return;
        if (_isChar(a, _semicolon)) {
          k = a + 1;
          break;
        }
        var j = a + 1;
        if (_isChar(j, _openAngle)) j = _afterAngles(j, close);
        if (_isChar(j, _dot)) j += 2;
        if (_isChar(j, _openParen) && _lexed.closerOf(j) > 0) {
          j = _lexed.closerOf(j) + 1;
        }
        if (_isChar(j, _openBrace) && _lexed.closerOf(j) > 0) {
          j = _lexed.closerOf(j) + 1;
        }
        _record(k, j - 1, annotations, '$owner.${_text(a)}');
        if (_isChar(j, _comma)) j++;
        k = j;
      }
    }
    while (k < close) {
      if (_isChar(k, _semicolon)) {
        k++;
        continue;
      }
      final annotations = <_Annotation>[];
      final a = _annotations(k, annotations);
      if (a >= close) return;
      final end = _declarationEnd(a, close);
      final header = _header(a, end, owner: owner);
      if (header != null) _record(k, end, annotations, header.name);
      k = end + 1;
    }
  }

  void _record(int first, int end, List<_Annotation> annotations, String name) {
    final relevant = [
      for (final annotation in annotations)
        if (!_ignoredAnnotations.contains(annotation.name)) annotation.name,
    ]..sort();
    if (relevant.isEmpty) return;
    final last = end >= _n ? _n - 1 : end;
    final lexemes = [for (var k = first; k <= last; k++) _text(k)];
    declarations.add(
      AnnotatedDeclaration(
        name: name,
        annotations: relevant,
        tokenHash: crypto.sha256
            .convert(utf8.encode(lexemes.join(' ')))
            .toString(),
        location: _location(annotations.first.start, annotations.last.end),
      ),
    );
  }

  /// The index of the last token of the declaration starting at [a]: the
  /// `;`, or the `}` of its body.
  int _declarationEnd(int a, int limit) {
    var k = a;
    var sawEquals = false;
    var sawColon = false;
    while (k < limit) {
      if (_isChar(k, _semicolon)) return k;
      if (_isChar(k, _openParen) || _isChar(k, _openBracket)) {
        k = _lexed.closerOf(k) < 0 ? limit : _lexed.closerOf(k) + 1;
        continue;
      }
      if (_isChar(k, _openBrace)) {
        final close = _lexed.closerOf(k) < 0 ? limit - 1 : _lexed.closerOf(k);
        final previous = k - 1;
        final isExpression =
            sawEquals ||
            (sawColon &&
                !(_isChar(previous, 0x29) ||
                    _isChar(previous, 0x7D) ||
                    (_isWord(previous) &&
                        !_isText(previous, 'const') &&
                        !_isText(previous, 'new'))));
        if (!isExpression) return close;
        k = close + 1;
        continue;
      }
      if (_lexed.kinds[k] == TokenKind.punctuation) {
        if (_isChar(k, _equals) || _isText(k, '=>')) {
          if (!sawColon) sawEquals = true;
        } else if (_isChar(k, _colon)) {
          sawColon = true;
        }
      }
      k++;
    }
    return limit - 1;
  }

  /// The name of the declaration at [a]..[end], and where its body opens,
  /// or null when it is not a kind that can be named.
  _Header? _header(int a, int end, {required String? owner}) {
    // Header tokens: up to the first `(`, `{`, `;`, `=`, `=>`, or a `,`, at
    // angle depth 0.
    var k = a;
    var angle = 0;
    var stop = -1;
    var classLike = -1;
    while (k <= end && k < _n) {
      if (angle == 0 &&
          _lexed.kinds[k] == TokenKind.word &&
          classLike < 0 &&
          (_isText(k, 'class') ||
              _isText(k, 'mixin') ||
              _isText(k, 'enum') ||
              _isText(k, 'extension') ||
              _isText(k, 'typedef'))) {
        classLike = k;
      }
      if (_lexed.kinds[k] == TokenKind.punctuation) {
        if (_isChar(k, _openAngle)) {
          angle++;
        } else if (_isChar(k, _closeAngle)) {
          if (angle > 0) angle--;
        } else if (_isText(k, '>>')) {
          angle = angle >= 2 ? angle - 2 : 0;
        } else if (angle == 0 &&
            (_isChar(k, _openParen) ||
                _isChar(k, _openBrace) ||
                _isChar(k, _semicolon) ||
                _isChar(k, _equals) ||
                _isText(k, '=>') ||
                _isChar(k, _comma))) {
          stop = k;
          break;
        }
      }
      k++;
    }
    if (classLike >= 0 && owner == null) return _classLike(classLike, end);
    if (stop < 0) return null;
    if (_isChar(stop, _openParen)) return _callable(a, stop, owner);
    // Variable, field, getter: the last word before the stop.
    var p = stop - 1;
    while (p >= a && !_isWord(p)) {
      p--;
    }
    if (p < a) return null;
    final name = _text(p);
    return _Header(owner == null ? name : '$owner.$name', -1);
  }

  /// A class, mixin, enum, extension or typedef whose keyword is at
  /// [keyword].
  _Header? _classLike(int keyword, int end) {
    final word = _text(keyword);
    var j = keyword;
    String? name;
    if (word == 'mixin' && _isText(j + 1, 'class')) j++;
    if (word == 'extension') {
      if (_isText(j + 1, 'type') && _isWord(j + 2)) {
        name = _text(j + 2);
      } else if (_isWord(j + 1) && !_isText(j + 1, 'on')) {
        name = _text(j + 1);
      } else {
        name = '<unnamed>';
      }
    } else if (word == 'typedef') {
      if (_isWord(j + 1) &&
          (_isChar(j + 2, _equals) || _isChar(j + 2, _openAngle))) {
        name = _text(j + 1);
      } else {
        // Old style: `typedef R Name(args);`
        var p = j + 1;
        while (p <= end && !_isChar(p, _openParen)) {
          p++;
        }
        name = _isWord(p - 1) ? _text(p - 1) : null;
      }
    } else if (_isWord(j + 1)) {
      name = _text(j + 1);
    }
    if (name == null) return null;
    var open = -1;
    for (var p = keyword; p <= end; p++) {
      if (_isChar(p, _openParen) && _lexed.closerOf(p) > 0) {
        p = _lexed.closerOf(p);
        continue;
      }
      if (_isChar(p, _openBrace)) {
        open = p;
        break;
      }
      if (_isChar(p, _semicolon) || _isChar(p, _equals)) break;
    }
    return _Header(name, open, isEnum: word == 'enum');
  }

  /// A function, method, constructor or operator whose parameters open at
  /// [paren].
  _Header? _callable(int a, int paren, String? owner) {
    // Skip type parameters: `name<T>(`.
    var nameToken = paren - 1;
    if (_isChar(nameToken, _closeAngle) || _isText(nameToken, '>>')) {
      var depth = 0;
      while (nameToken >= a) {
        if (_isChar(nameToken, _closeAngle)) depth++;
        if (_isText(nameToken, '>>')) depth += 2;
        if (_isChar(nameToken, _openAngle)) depth--;
        nameToken--;
        if (depth <= 0) break;
      }
    }
    if (nameToken < a) return null;
    if (owner == null) {
      return _isWord(nameToken) ? _Header(_text(nameToken), -1) : null;
    }
    // `Owner`, `Owner.named`, `factory Owner.named`, operators.
    if (_isWord(nameToken) &&
        _isChar(nameToken - 1, _dot) &&
        _isText(nameToken - 2, owner)) {
      return _Header('$owner.${_text(nameToken)}', -1);
    }
    if (_isText(nameToken, owner)) return _Header('$owner.new', -1);
    if (_isText(nameToken - 1, 'operator')) {
      return _Header('$owner.${_text(nameToken)}', -1);
    }
    if (!_isWord(nameToken)) {
      var p = nameToken;
      while (p > a && !_isText(p, 'operator')) {
        p--;
      }
      return _isText(p, 'operator')
          ? _Header('$owner.${_text(p + 1)}', -1)
          : null;
    }
    return _Header('$owner.${_text(nameToken)}', -1);
  }
}

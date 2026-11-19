/// Directive URIs through a hand-written scanner.
library;

/// Returns the same URIs as `directivesByParser`, without a parser.
///
/// Scans from the top of [source], skipping whitespace, comments, a script
/// tag and annotations, and stops at the first token that does not start
/// a directive. Inside a directive, string literals at parenthesis depth 0
/// are URIs (the condition of a configuration is inside parentheses);
/// adjacent literals are concatenated.
List<String> directivesByScanner(String source) =>
    _Scanner(source).directives();

final class _Scanner {
  new(this._s);

  final String _s;
  var _i = 0;

  bool get _done => _i >= _s.length;
  int get _c => _s.codeUnitAt(_i);

  List<String> directives() {
    final uris = <String>[];
    if (_s.startsWith('#!')) _skipLine();
    while (true) {
      _skipTrivia();
      if (_done) return uris;
      if (_c == 0x40 /* @ */ ) {
        _skipAnnotation();
        continue;
      }
      final word = _identifier();
      switch (word) {
        case 'library':
          _skipDirective(null);
        case 'import' || 'export':
          _skipDirective(uris);
        case 'part':
          _skipTrivia();
          final save = _i;
          if (_identifier() == 'of') {
            _skipDirective(uris);
          } else {
            _i = save;
            _skipDirective(uris);
          }
        default:
          return uris;
      }
    }
  }

  /// Reads up to the `;` that ends a directive, adding URIs to [uris].
  void _skipDirective(List<String>? uris) {
    var depth = 0;
    var previousWasString = false;
    while (!_done) {
      _skipTrivia();
      if (_done) return;
      final c = _c;
      if (c == 0x3B /* ; */ && depth == 0) {
        _i++;
        return;
      } else if (c == 0x28 /* ( */ ) {
        depth++;
        _i++;
        previousWasString = false;
      } else if (c == 0x29 /* ) */ ) {
        depth--;
        _i++;
        previousWasString = false;
      } else if (_startsString()) {
        final value = _string();
        if (depth == 0 && uris != null) {
          if (previousWasString) {
            uris[uris.length - 1] += value;
          } else {
            uris.add(value);
          }
          previousWasString = true;
        }
      } else {
        _i++;
        previousWasString = false;
      }
    }
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

  String _string() {
    if (_c == 0x72 || _c == 0x52) _i++;
    final quote = _s[_i];
    final triple = _s.startsWith(quote * 3, _i);
    final end = triple ? quote * 3 : quote;
    _i += end.length;
    final start = _i;
    final close = _s.indexOf(end, _i);
    _i = close < 0 ? _s.length : close + end.length;
    return _s.substring(start, close < 0 ? _s.length : close);
  }

  void _skipAnnotation() {
    _i++; // @
    _identifier();
    while (!_done && _c == 0x2E /* . */ ) {
      _i++;
      _identifier();
    }
    _skipTrivia();
    if (!_done && _c == 0x28 /* ( */ ) {
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

  // Dart block comments nest.
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
}

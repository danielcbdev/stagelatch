/// Minimal XML 1.0 writer for the JUnit reporter.
///
/// This is the only place that emits `<` or `&` into report output (S5).
library;

/// Escapes [text] for XML 1.0 character data or an attribute value.
///
/// Drops characters the XML 1.0 `Char` production forbids. Always escapes
/// `&`, `<` and `>`; with [attribute] also escapes `"` and `'`.
String escapeXml(String text, {required bool attribute}) {
  final buffer = StringBuffer();
  for (final unit in text.runes) {
    if (!_isXml10Char(unit)) continue;
    switch (unit) {
      case 0x26: // &
        buffer.write('&amp;');
      case 0x3C: // <
        buffer.write('&lt;');
      case 0x3E: // >
        buffer.write('&gt;');
      case 0x22 when attribute: // "
        buffer.write('&quot;');
      case 0x27 when attribute: // '
        buffer.write('&apos;');
      default:
        buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// Whether [codePoint] is allowed in XML 1.0 character data.
bool _isXml10Char(int codePoint) =>
    codePoint == 0x9 ||
    codePoint == 0xA ||
    codePoint == 0xD ||
    (codePoint >= 0x20 && codePoint <= 0xD7FF) ||
    (codePoint >= 0xE000 && codePoint <= 0xFFFD) ||
    (codePoint >= 0x10000 && codePoint <= 0x10FFFF);

/// Writes well-formed XML elements to a [StringSink].
final class XmlWriter {
  /// Creates a writer that appends to the given sink.
  new(this._out);

  final StringSink _out;
  final List<String> _open = [];

  /// Opens `[name]` with unescaped [attributes] values.
  void startElement(String name, [Map<String, String> attributes = const {}]) {
    _writeStart(name, attributes, empty: false);
    _open.add(name);
  }

  /// Closes the most recently opened element.
  void endElement() {
    final name = _open.removeLast();
    _out
      ..write('</')
      ..write(name)
      ..write('>');
  }

  /// Writes a self-closing `[name]` element.
  void emptyElement(String name, [Map<String, String> attributes = const {}]) {
    _writeStart(name, attributes, empty: true);
  }

  /// Writes character data, escaping as needed.
  void text(String value) {
    _out.write(escapeXml(value, attribute: false));
  }

  void _writeStart(
    String name,
    Map<String, String> attributes, {
    required bool empty,
  }) {
    _out
      ..write('<')
      ..write(name);
    for (final entry in attributes.entries) {
      _out
        ..write(' ')
        ..write(entry.key)
        ..write('="')
        ..write(escapeXml(entry.value, attribute: true))
        ..write('"');
    }
    _out.write(empty ? '/>' : '>');
  }
}

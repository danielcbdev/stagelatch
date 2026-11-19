/// Strips characters a terminal would act on (security rules S5 and S6).
library;

/// Returns [text] with terminal controls removed, in one forward pass.
///
/// C0 controls, DEL (U+007F) and C1 controls are dropped. Newline (U+000A)
/// and tab (U+0009) become one space each, so a value cannot forge a new
/// line or a new column. Carriage return is a C0 control and is dropped,
/// which turns a CRLF pair into that single space. The bidirectional
/// controls U+200E, U+200F, U+202A–U+202E and U+2066–U+2069 are dropped
/// too: they can reorder the characters around them. Everything else,
/// including non-ASCII letters, is copied unchanged.
///
/// The scan looks at each code point once and never backtracks, so its
/// cost is linear in the length of [text] (S6).
String sanitizeForTerminal(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0x09 || rune == 0x0A) {
      buffer.write(' ');
    } else if (_isTerminalControl(rune)) {
      continue;
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// C0 (other than tab and newline, which the caller rewrites), DEL, C1,
/// and the bidirectional controls named in security rule S5.
bool _isTerminalControl(int rune) =>
    rune <= 0x1F ||
    rune == 0x7F ||
    (rune >= 0x80 && rune <= 0x9F) ||
    rune == 0x200E ||
    rune == 0x200F ||
    (rune >= 0x202A && rune <= 0x202E) ||
    (rune >= 0x2066 && rune <= 0x2069);

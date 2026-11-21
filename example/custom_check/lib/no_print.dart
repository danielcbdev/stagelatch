/// Finds top-level-looking `print(` calls for the example custom check.
library;

/// Match for a Dart `print(` call (intentionally simple; not a full parser).
final RegExp printCallPattern = RegExp(r'\bprint\s*\(');

/// Returns 1-based line/column of the first [printCallPattern] match, or null.
({int line, int column})? findPrintCall(String source) {
  final match = printCallPattern.firstMatch(source);
  if (match == null) {
    return null;
  }
  final before = source.substring(0, match.start);
  final line = '\n'.allMatches(before).length + 1;
  final lastNewline = before.lastIndexOf('\n');
  final column = match.start - lastNewline;
  return (line: line, column: column);
}

import 'dart:io';

import 'package:test/test.dart';

/// The patterns of an ignore file: one per line, comments and blanks out.
List<String> _patterns(String path) => [
  for (final line in File(path).readAsLinesSync())
    if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#')) line.trim(),
];

void main() {
  // pub reads .pubignore instead of .gitignore in the same directory, so a
  // path ignored by git (coverage output, scratch space) would otherwise be
  // published from a working checkout.
  test('.pubignore repeats every pattern of .gitignore', () {
    final published = _patterns('.pubignore');

    expect(
      _patterns('.gitignore').where((pattern) => !published.contains(pattern)),
      isEmpty,
    );
  });
}

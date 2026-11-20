/// Where two texts start to differ.
library;

import 'package:stagelatch/src/domain/location.dart';

/// The 1-based line and column of the first character where [a] and [b]
/// differ. When one is a prefix of the other, the position just after the
/// shorter one. A line ends at `\n`; a `\r` before it is part of the line.
Position firstDifference(String a, String b) {
  var line = 1;
  var column = 1;
  final length = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final unit = a.codeUnitAt(i);
    if (unit != b.codeUnitAt(i)) return Position(line, column);
    if (unit == 0x0A) {
      line++;
      column = 1;
    } else {
      column++;
    }
  }
  return Position(line, column);
}

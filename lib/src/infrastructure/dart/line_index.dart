/// Offsets to lines and columns.
library;

import 'package:stagelatch/src/domain/location.dart';

/// Turns offsets of a text into 1-based [Position]s.
///
/// A line ends at `\n`; a `\r` before it belongs to the line. Line starts
/// are found once, on the first question, and answers are a binary search.
final class LineIndex {
  /// Creates an index over the text.
  new(this._text);

  final String _text;
  List<int>? _starts;

  /// The position of [offset] in the text.
  Position positionOf(int offset) {
    final starts = _starts ??= [
      0,
      for (var i = 0; i < _text.length; i++)
        if (_text.codeUnitAt(i) == 0x0A) i + 1,
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

/// Sizes as the `assets/max-file-size` message prints them.
library;

const _units = ['B', 'KB', 'MB', 'GB'];

/// The unit a size is printed in, picked from [limit], so a size and the
/// limit it broke read in the same unit.
int _unitIndex(int limit) {
  var index = 0;
  var unit = 1024;
  while (index < _units.length - 1 && limit >= unit) {
    index++;
    unit *= 1024;
  }
  return index;
}

String _tenths(int bytes, int unit) {
  // Round half up, on integers, so the text never depends on floating
  // point.
  final tenths = (bytes * 10 + unit ~/ 2) ~/ unit;
  return '${tenths ~/ 10}.${tenths % 10}';
}

/// [bytes] with one decimal, in the unit of [limit]: `612.4KB` for a limit
/// of 500 KB. Units are binary, as in the configuration: 1 KB is 1,024
/// bytes.
String formatSize(int bytes, {required int limit}) {
  final index = _unitIndex(limit);
  return '${_tenths(bytes, 1 << (10 * index))}${_units[index]}';
}

/// [limit] in its own unit: `500KB`, or `1.5MB` when it is not a whole
/// number of that unit.
String formatLimit(int limit) {
  final index = _unitIndex(limit);
  final unit = 1 << (10 * index);
  if (limit % unit == 0) return '${limit ~/ unit}${_units[index]}';
  return '${_tenths(limit, unit)}${_units[index]}';
}

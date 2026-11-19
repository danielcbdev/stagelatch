/// Parsers for the size and duration values of the configuration.
library;

/// `<digits><unit>`. Fixed alternatives and one bounded quantifier, so
/// matching is linear (security rule S6). Fifteen digits keep the product
/// below 2^63 even for megabytes.
final _size = RegExp(r'^(\d{1,15})(B|KB|MB)$');

final _milliseconds = RegExp(r'^(\d{1,9})ms$');

final _seconds = RegExp(r'^(\d{1,9}(?:\.\d{1,6})?)s$');

/// Parses a size such as `500KB` into bytes.
///
/// The value is a non-negative integer directly followed by `B`, `KB` or
/// `MB`. Units are binary: `1KB` is 1024 bytes and `1MB` is 1024 KB
/// (docs/specs/config.md, section 4).
///
/// Throws [FormatException] for anything else.
int parseSize(String value) {
  final match = _size.firstMatch(value);
  if (match == null) throw FormatException('Not a size.', value);
  final amount = int.parse(match.group(1) ?? '');
  return amount *
      switch (match.group(2)) {
        'KB' => 1024,
        'MB' => 1024 * 1024,
        _ => 1,
      };
}

/// Parses a duration such as `250ms` or `1.5s`.
///
/// Milliseconds are a whole number; seconds may have up to six decimals.
/// The result must be greater than zero.
///
/// Throws [FormatException] for anything else.
Duration parseDuration(String value) {
  final duration = switch ((
    _milliseconds.firstMatch(value),
    _seconds.firstMatch(value),
  )) {
    (final match?, _) => Duration(
      milliseconds: int.parse(match.group(1) ?? ''),
    ),
    (_, final match?) => Duration(
      microseconds: (double.parse(match.group(1) ?? '') * 1000000).round(),
    ),
    _ => throw FormatException('Not a duration.', value),
  };
  if (duration <= Duration.zero) {
    throw FormatException('A duration must be greater than zero.', value);
  }
  return duration;
}

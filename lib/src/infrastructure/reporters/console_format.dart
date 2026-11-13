/// Renders durations and counts for the console reporter.
library;

/// How long [duration] took, for one row of the check table.
///
/// Below one second this is whole milliseconds (`6ms`). From one second
/// on it is seconds with one decimal (`1.0s`). The tenth is chosen with
/// integer arithmetic, so the same input renders the same way on every
/// machine (ADR-0003).
String formatDuration(Duration duration) {
  final milliseconds = duration.inMilliseconds;
  if (milliseconds < 1000) return '${milliseconds}ms';
  return formatSeconds(duration);
}

/// [duration] as seconds with one decimal, including below one second.
///
/// `917ms` is `0.9s`. Rounding uses integer arithmetic: the nearest tenth
/// of a second, with a tie rounding away from zero.
String formatSeconds(Duration duration) {
  final tenths = (duration.inMilliseconds + 50) ~/ 100;
  final whole = tenths ~/ 10;
  final fraction = tenths.remainder(10);
  return '$whole.${fraction}s';
}

/// The configured time budget.
///
/// An exact number of seconds is printed as seconds (`2s`). Anything else
/// is printed as milliseconds (`1500ms`), which is how the config spells
/// a budget that is not a whole number of seconds.
String formatBudget(Duration duration) {
  final milliseconds = duration.inMilliseconds;
  if (milliseconds % 1000 == 0) return '${milliseconds ~/ 1000}s';
  return '${milliseconds}ms';
}

/// [count] followed by [singular], or its plural when [count] is not 1.
///
/// The plural is [singular] with `s` appended, unless [plural] is given
/// (`entry` / `entries`). Zero takes the plural: `0 errors`.
String counted(int count, String singular, {String? plural}) {
  final word = count == 1 ? singular : (plural ?? '${singular}s');
  return '$count $word';
}

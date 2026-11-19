/// Renders durations, counts and the summary for the console and GitHub
/// reporters.
library;

import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/severity.dart';

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

/// The summary of [report]: counts, outcome and total time, followed by a
/// second line when anything was suppressed or baselined
/// (docs/specs/cli.md, section 4). No trailing newline.
String summaryLine(RunReport report) {
  final errors = report.findings
      .where((finding) => finding.severity == Severity.error)
      .length;
  final warnings = report.findings.length - errors;
  final outcome = switch ((report.entry, report.verdict)) {
    (EntryKind.preCommit, Verdict.fail) => 'Commit blocked',
    (EntryKind.preCommit, Verdict.pass) => 'Commit allowed',
    (EntryKind.prePush, Verdict.fail) => 'Push blocked',
    (EntryKind.prePush, Verdict.pass) => 'Push allowed',
    (EntryKind.ci, Verdict.fail) => 'Failed',
    (EntryKind.ci, Verdict.pass) => 'Passed',
  };
  final counts = counted(errors, 'error');
  final warningCounts = counted(warnings, 'warning');
  final total = formatSeconds(report.total);
  return [
    '$counts, $warningCounts. $outcome. ($total)',
    if (report.suppressed > 0 || report.baselined > 0)
      '(${report.suppressed} suppressed, ${report.baselined} baselined)',
  ].join('\n');
}

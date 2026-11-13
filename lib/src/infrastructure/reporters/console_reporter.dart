/// The terminal reporter (docs/specs/cli.md section 4).
library;

import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/application/ports/reporter.dart';
import 'package:stagelatch/src/application/text/sanitize.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/reporters/ansi.dart';
import 'package:stagelatch/src/infrastructure/reporters/console_format.dart';

/// Second line of a fix whose working tree copy was left untouched.
///
/// docs/specs/cli.md section 4. Kept as one string so the list of lines
/// does not concatenate adjacent literals.
const _indexOnly =
    '  Fixed in the index only: the working tree copy has unstaged changes.';

/// Writes one invocation to a terminal, or to any [StringSink].
///
/// Sections of a run (header, check table, details, notes, summary) are
/// separated by one blank line, and a section with nothing to say is
/// omitted. Several runs are separated the same way. Every string that
/// came from the repository is passed through `sanitizeForTerminal`
/// before it is written (security rule S5).
final class ConsoleReporter implements Reporter {
  /// Creates a reporter writing to the given sink.
  ///
  /// When [color] is true, severities and rule ids are wrapped in SGR
  /// sequences. The text underneath is the same either way.
  const new(this._out, {required this.color});

  final StringSink _out;

  /// Whether severities and rule ids are colored.
  final bool color;

  @override
  void report(List<RunReport> runs) {
    if (runs.isEmpty) {
      _out.writeln('stagelatch: nothing to check.');
      return;
    }
    _out.writeln(runs.map(_render).join('\n\n'));
  }

  String _render(RunReport report) {
    final notes = _notes(report);
    final sections = <String>[
      _header(report),
      if (report.timings.isNotEmpty) _table(report.timings),
      if (report.fixes.isNotEmpty || report.findings.isNotEmpty)
        _details(report),
      if (notes.isNotEmpty) notes.join('\n'),
      _summary(report),
    ];
    return sections.join('\n\n');
  }

  String _header(RunReport report) {
    final entry = switch (report.entry) {
      EntryKind.preCommit => 'pre-commit',
      EntryKind.prePush => 'pre-push ${sanitizeForTerminal(report.label)}',
      EntryKind.ci => 'ci',
    };
    return 'stagelatch $entry: ${counted(report.files, 'file')}';
  }

  /// One row per check that ran, in the order the report lists them.
  ///
  /// The id and the status are aligned left and the duration is aligned
  /// right. Columns are separated by two spaces, and each column is as
  /// wide as its widest cell.
  String _table(List<CheckTiming> timings) {
    final rows = [
      for (final timing in timings)
        (timing.id, _status(timing), formatDuration(timing.duration)),
    ];
    final idWidth = _widest(rows.map((row) => row.$1));
    final statusWidth = _widest(rows.map((row) => row.$2));
    final durationWidth = _widest(rows.map((row) => row.$3));
    return [
      for (final row in rows)
        _checkRow(row, idWidth, statusWidth, durationWidth),
    ].join('\n');
  }

  String _checkRow(
    (String, String, String) row,
    int idWidth,
    int statusWidth,
    int durationWidth,
  ) {
    final id = row.$1.padRight(idWidth);
    final status = row.$2.padRight(statusWidth);
    final duration = row.$3.padLeft(durationWidth);
    return '  $id  $status  $duration';
  }

  /// Errors and warnings outrank a fix count: a check that both fixed a
  /// file and still has findings shows the findings. `ok` means neither.
  String _status(CheckTiming timing) {
    final problems = [
      if (timing.errors > 0) counted(timing.errors, 'error'),
      if (timing.warnings > 0) counted(timing.warnings, 'warning'),
    ];
    if (problems.isNotEmpty) return problems.join(', ');
    if (timing.fixed > 0) return 'fixed ${counted(timing.fixed, 'file')}';
    return 'ok';
  }

  String _details(RunReport report) => [
    for (final fix in report.fixes) ..._fixLines(fix),
    for (final finding in report.findings) ..._findingLines(finding),
  ].join('\n');

  List<String> _fixLines(AppliedFix fix) {
    final path = sanitizeForTerminal(fix.path.value);
    final rule = _rule(fix.rule.toString());
    final lines = <String>['$path  fixed  $rule'];
    if (!fix.worktreeUpdated) lines.add(_indexOnly);
    return lines;
  }

  List<String> _findingLines(Finding finding) {
    final path = sanitizeForTerminal(finding.location.path.value);
    final line = finding.location.start.line;
    final column = finding.location.start.column;
    final severity = _severity(finding.severity);
    final rule = _rule(finding.rule.toString());
    final message = sanitizeForTerminal(finding.message);
    return ['$path:$line:$column  $severity  $rule', '  $message'];
  }

  List<String> _notes(RunReport report) => [
    for (final notice in report.notices) 'note: ${sanitizeForTerminal(notice)}',
    if (report.budgetExceeded) _budgetNote(report),
  ];

  String _budgetNote(RunReport report) {
    final budget = formatBudget(report.timeBudget);
    final total = formatSeconds(report.total);
    return 'note: Time budget of $budget exceeded ($total).';
  }

  String _summary(RunReport report) {
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

  String _severity(Severity severity) {
    final (label, code) = switch (severity) {
      Severity.error => ('error', ansiError),
      Severity.warning => ('warning', ansiWarning),
    };
    return color ? ansi(label, code) : label;
  }

  String _rule(String id) => color ? ansi(id, ansiDim) : id;

  int _widest(Iterable<String> values) {
    var width = 0;
    for (final value in values) {
      if (value.length > width) width = value.length;
    }
    return width;
  }
}

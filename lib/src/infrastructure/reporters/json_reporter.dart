/// The JSON report (docs/specs/cli.md, section 5).
library;

import 'dart:convert';

import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/reporter.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The version of the report's shape. It changes only on a breaking change.
const int jsonSchemaVersion = 1;

/// Writes every run of one invocation as one JSON object, for scripts and
/// AI agents that must not parse terminal text.
///
/// Maps are built in the documented key order and encoded by
/// `JsonEncoder`; no string is ever concatenated into the output (S5).
/// Everything except the `durationMs` fields is deterministic (ADR-0003).
final class JsonReporter implements Reporter {
  /// Creates a reporter that writes to `out`.
  new(this._out, {required this._toolVersion});

  final StringSink _out;
  final String _toolVersion;

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  @override
  void report(List<RunReport> runs) {
    final Map<String, Object?> object;
    if (runs.length == 1) {
      object = {
        'schemaVersion': jsonSchemaVersion,
        'stagelatchVersion': _toolVersion,
        ..._run(runs.single),
      };
    } else {
      // Several pushed refs, or none at all (a tag push, a deletion): each
      // run keeps its own verdict, and the top level carries the outcome.
      final failed = runs.any((run) => run.verdict == Verdict.fail);
      object = {
        'schemaVersion': jsonSchemaVersion,
        'stagelatchVersion': _toolVersion,
        'verdict': failed ? 'fail' : 'pass',
        'exitCode': failed ? 1 : 0,
        'runs': [for (final run in runs) _run(run)],
      };
    }
    _out.writeln(_encoder.convert(object));
  }

  Map<String, Object?> _run(RunReport run) => {
    'entry': _entry(run.entry),
    'verdict': run.verdict == Verdict.fail ? 'fail' : 'pass',
    'exitCode': run.verdict == Verdict.fail ? 1 : 0,
    'files': run.files,
    'findings': [for (final finding in run.findings) _finding(finding)],
    'fixes': [
      for (final fix in run.fixes)
        {
          'rule': fix.rule.toString(),
          'path': fix.path.value,
          'worktreeUpdated': fix.worktreeUpdated,
        },
    ],
    'checks': [
      for (final timing in run.timings)
        {
          'id': timing.id,
          'durationMs': timing.duration.inMilliseconds,
          'errors': timing.errors,
          'warnings': timing.warnings,
          'fixed': timing.fixed,
        },
    ],
    'suppressed': run.suppressed,
    'baselined': run.baselined,
    'notices': run.notices,
    'durationMs': run.total.inMilliseconds,
    'timeBudgetExceeded': run.budgetExceeded,
  };

  static Map<String, Object?> _finding(Finding finding) => {
    'rule': finding.rule.toString(),
    'severity': finding.severity == Severity.error ? 'error' : 'warning',
    'path': finding.location.path.value,
    'line': finding.location.start.line,
    'column': finding.location.start.column,
    'endLine': finding.location.end.line,
    'endColumn': finding.location.end.column,
    'message': finding.message,
  };

  static String _entry(EntryKind entry) => switch (entry) {
    EntryKind.preCommit => 'pre-commit',
    EntryKind.prePush => 'pre-push',
    EntryKind.ci => 'ci',
  };
}

/// The object printed on stdout instead of a report when the command ends
/// with exit code 64, 70 or 78. [kind] is `usage`, `internal` or `config`.
String renderErrorJson({
  required String kind,
  required String message,
  required int exitCode,
}) => jsonEncode({
  'schemaVersion': jsonSchemaVersion,
  'error': {'kind': kind, 'message': message},
  'exitCode': exitCode,
});

/// GitHub Actions workflow commands (docs/specs/cli.md, section 6).
library;

import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/reporter.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/reporters/console_format.dart';

/// Escapes the message part of a workflow command, after the second `::`.
///
/// Without it, a newline in an analyzer message would end the command and
/// let repository content start another one (security S5).
String escapeWorkflowData(String value) => value
    .replaceAll('%', '%25')
    .replaceAll('\r', '%0D')
    .replaceAll('\n', '%0A');

/// Escapes a property value of a workflow command, such as `file` or
/// `title`, where `:` and `,` are separators.
String escapeWorkflowProperty(String value) =>
    escapeWorkflowData(value).replaceAll(':', '%3A').replaceAll(',', '%2C');

/// Writes one `::error` or `::warning` command per finding, so the pull
/// request shows each one on its line, then the console summary.
final class GithubReporter implements Reporter {
  /// Creates a reporter that writes to `out`.
  new(this._out);

  final StringSink _out;

  @override
  void report(List<RunReport> runs) {
    if (runs.isEmpty) {
      _out.writeln('stagelatch: nothing to check.');
      return;
    }
    for (final run in runs) {
      for (final finding in run.findings) {
        _out.writeln(_command(finding));
      }
    }
    for (final run in runs) {
      _out.writeln(summaryLine(run));
    }
  }

  static String _command(Finding finding) {
    final kind = finding.severity == Severity.error ? 'error' : 'warning';
    final location = finding.location;
    final properties = [
      'file=${escapeWorkflowProperty(location.path.value)}',
      'line=${location.start.line}',
      'col=${location.start.column}',
      'endLine=${location.end.line}',
      'endColumn=${location.end.column}',
      'title=${escapeWorkflowProperty(finding.rule.toString())}',
    ].join(',');
    return '::$kind $properties::${escapeWorkflowData(finding.message)}';
  }
}

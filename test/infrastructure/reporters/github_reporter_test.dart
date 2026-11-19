import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/reporters/github_reporter.dart';
import 'package:test/test.dart';

const _pathDependencyMessage =
    'Dependency "design_system" uses a path that is not a package in this '
    'repository: ../design_system.';

const _invalidIgnoreMessage = 'Unknown rule "x/y" in stagelatch:ignore.';

Finding _finding(
  String path,
  String rule,
  String message, {
  Severity severity = Severity.error,
  int line = 14,
  int column = 5,
  int endColumn = 26,
}) => Finding(
  rule: RuleId.parse(rule),
  severity: severity,
  message: message,
  location: Location(
    RepoPath(path),
    Position(line, column),
    Position(line, endColumn),
  ),
);

RunReport _report(List<Finding> findings, {int suppressed = 0}) => RunReport(
  entry: EntryKind.ci,
  label: 'main',
  files: 3,
  verdict: findings.any((finding) => finding.severity == Severity.error)
      ? Verdict.fail
      : Verdict.pass,
  findings: findings,
  fixes: const [],
  timings: const [],
  total: const Duration(milliseconds: 1240),
  timeBudget: const Duration(seconds: 2),
  budgetExceeded: false,
  suppressed: suppressed,
  baselined: 0,
  notices: const [],
);

List<String> _lines(List<RunReport> runs) {
  final out = StringBuffer();
  GithubReporter(out).report(runs);
  return out.toString().split('\n');
}

void main() {
  test('data escapes percent, CR and LF', () {
    expect(escapeWorkflowData('50%\r\nx'), '50%25%0D%0Ax');
    expect(escapeWorkflowData('a:b,c'), 'a:b,c');
  });

  test('properties also escape colon and comma', () {
    expect(escapeWorkflowProperty('a:b,c'), 'a%3Ab%2Cc');
    expect(escapeWorkflowProperty('5%\n'), '5%25%0A');
  });

  test('an error renders one command line', () {
    final lines = _lines([
      _report([
        _finding(
          'pubspec.yaml',
          'pubspec/path-dependency',
          _pathDependencyMessage,
        ),
      ]),
    ]);

    expect(
      lines.first,
      '::error '
      'file=pubspec.yaml,line=14,col=5,endLine=14,endColumn=26,'
      'title=pubspec/path-dependency::$_pathDependencyMessage',
    );
  });

  test('a warning uses ::warning', () {
    final lines = _lines([
      _report([
        _finding(
          'lib/a.dart',
          'stagelatch/invalid-ignore',
          _invalidIgnoreMessage,
          severity: Severity.warning,
          line: 2,
          column: 22,
          endColumn: 25,
        ),
      ]),
    ]);

    expect(
      lines.first,
      '::warning '
      'file=lib/a.dart,line=2,col=22,endLine=2,endColumn=25,'
      'title=stagelatch/invalid-ignore::$_invalidIgnoreMessage',
    );
  });

  test('a message carrying a newline and a workflow command cannot start a '
      'new command', () {
    final lines = _lines([
      _report([_finding('a.yaml', 'a/b', 'x\n::set-output name=a::b')]),
    ]);

    expect(lines.where((line) => line.startsWith('::')), hasLength(1));
    expect(lines.first, endsWith('::x%0A::set-output name=a::b'));
  });

  test('a path with a comma or colon is escaped as a property', () {
    final lines = _lines([
      _report([_finding('a,b:c.yaml', 'a/b', 'm')]),
    ]);

    expect(lines.first, startsWith('::error file=a%2Cb%3Ac.yaml,line=14,'));
  });

  test('the console summary line follows the commands', () {
    final lines = _lines([
      _report([
        _finding('a.yaml', 'a/b', 'm'),
        _finding('b.yaml', 'a/b', 'n', severity: Severity.warning),
      ], suppressed: 2),
    ]);

    expect(lines.sublist(2), [
      '1 error, 1 warning. Failed. (1.2s)',
      '(2 suppressed, 0 baselined)',
      '',
    ]);
  });

  test('no run at all prints the console notice', () {
    expect(_lines(const []), ['stagelatch: nothing to check.', '']);
  });
}

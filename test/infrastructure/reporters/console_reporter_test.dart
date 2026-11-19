import 'dart:io';

import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/reporters/console_reporter.dart';
import 'package:test/test.dart';

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

Finding _finding(
  String path,
  int line,
  int column,
  String rule,
  String message, {
  Severity severity = Severity.error,
}) => Finding(
  rule: RuleId.parse(rule),
  severity: severity,
  message: message,
  location: Location(
    RepoPath(path),
    Position(line, column),
    Position(line, column + 1),
  ),
);

CheckTiming _timing(
  String id,
  int milliseconds, {
  int errors = 0,
  int warnings = 0,
  int fixed = 0,
}) => CheckTiming(
  id: id,
  duration: _ms(milliseconds),
  errors: errors,
  warnings: warnings,
  fixed: fixed,
);

RunReport _report({
  EntryKind entry = EntryKind.preCommit,
  String label = 'index',
  int files = 1,
  List<Finding> findings = const [],
  List<AppliedFix> fixes = const [],
  List<CheckTiming> timings = const [],
  int totalMs = 120,
  bool budgetExceeded = false,
  int suppressed = 0,
  int baselined = 0,
  List<String> notices = const [],
}) => RunReport(
  entry: entry,
  label: label,
  files: files,
  verdict: findings.any((finding) => finding.severity == Severity.error)
      ? Verdict.fail
      : Verdict.pass,
  findings: findings,
  fixes: fixes,
  timings: timings,
  total: _ms(totalMs),
  timeBudget: const Duration(seconds: 2),
  budgetExceeded: budgetExceeded,
  suppressed: suppressed,
  baselined: baselined,
  notices: notices,
);

String _render(List<RunReport> runs, {bool color = false}) {
  final out = StringBuffer();
  ConsoleReporter(out, color: color).report(runs);
  return out.toString();
}

String _golden(String name) =>
    File('test/goldens/console/$name.txt').readAsStringSync();

final RunReport _blocked = _report(
  files: 4,
  totalMs: 917,
  timings: [
    _timing('format', 41, fixed: 1),
    _timing('analyze', 870),
    _timing('pubspec', 6, errors: 1),
  ],
  fixes: [
    AppliedFix(
      rule: const RuleId('format', 'unformatted'),
      path: RepoPath('lib/checkout/cart.dart'),
      worktreeUpdated: true,
    ),
  ],
  findings: [
    _finding(
      'pubspec.yaml',
      14,
      5,
      'pubspec/path-dependency',
      'Dependency "design_system" uses a path that is not a package in this '
          'repository: ../design_system.',
    ),
  ],
);

void main() {
  group('goldens', () {
    test('a blocked commit', () {
      expect(_render([_blocked]), _golden('blocked'));
    });

    test('a clean run', () {
      final report = _report(timings: [_timing('pubspec', 3)]);

      expect(_render([report]), _golden('clean'));
    });

    test('everything at once', () {
      final report = _report(
        files: 12,
        totalMs: 2400,
        budgetExceeded: true,
        suppressed: 2,
        baselined: 5,
        notices: [
          'stagelatch.yaml is not staged; using the working tree copy.',
        ],
        timings: [
          _timing('format', 40, fixed: 1),
          _timing('analyze', 1234, errors: 1, warnings: 2),
          _timing('pubspec', 3),
        ],
        fixes: [
          AppliedFix(
            rule: const RuleId('format', 'unformatted'),
            path: RepoPath('lib/z.dart'),
            worktreeUpdated: false,
          ),
        ],
        findings: [
          _finding(
            'lib/a.dart',
            3,
            7,
            'analyze/undefined_identifier',
            "Undefined name 'x'.",
          ),
          _finding(
            'lib/a.dart',
            9,
            1,
            'analyze/unused_import',
            "Unused import: 'dart:io'.",
            severity: Severity.warning,
          ),
          _finding(
            'lib/b.dart',
            1,
            1,
            'analyze/unused_import',
            "Unused import: 'dart:async'.",
            severity: Severity.warning,
          ),
        ],
      );

      expect(_render([report]), _golden('full'));
    });
  });

  group('header and outcome', () {
    test('pre-push names the branch and speaks of the push', () {
      final passed = _render([
        _report(entry: EntryKind.prePush, label: 'feature/login', files: 2),
      ]);
      final failed = _render([
        _report(
          entry: EntryKind.prePush,
          label: 'feature/login',
          findings: [_finding('a.dart', 1, 1, 'analyze/x', 'm')],
        ),
      ]);

      expect(
        passed,
        startsWith('stagelatch pre-push feature/login: 2 files\n'),
      );
      expect(passed, contains('0 errors, 0 warnings. Push allowed. (0.1s)\n'));
      expect(failed, contains('1 error, 0 warnings. Push blocked. (0.1s)\n'));
    });

    test('ci passes or fails', () {
      final passed = _render([_report(entry: EntryKind.ci, files: 3)]);
      final failed = _render([
        _report(
          entry: EntryKind.ci,
          findings: [_finding('a.dart', 1, 1, 'analyze/x', 'm')],
        ),
      ]);

      expect(passed, startsWith('stagelatch ci: 3 files\n'));
      expect(passed, contains('Passed. (0.1s)\n'));
      expect(failed, contains('Failed. (0.1s)\n'));
    });

    test('counts files in the singular and in the plural', () {
      expect(
        _render([_report(files: 0)]),
        startsWith('stagelatch pre-commit: 0 files\n'),
      );
      expect(
        _render([_report()]),
        startsWith('stagelatch pre-commit: 1 file\n'),
      );
    });

    test('counts errors and warnings in the singular and in the plural', () {
      final output = _render([
        _report(
          findings: [
            _finding('a.dart', 1, 1, 'analyze/x', 'm'),
            _finding('b.dart', 1, 1, 'analyze/x', 'm'),
            _finding(
              'c.dart',
              1,
              1,
              'analyze/y',
              'm',
              severity: Severity.warning,
            ),
          ],
        ),
      ]);

      expect(output, contains('2 errors, 1 warning. Commit blocked.'));
    });
  });

  group('layout', () {
    test('with no check and no finding, only header and summary remain', () {
      expect(
        _render([_report()]),
        'stagelatch pre-commit: 1 file\n'
        '\n'
        '0 errors, 0 warnings. Commit allowed. (0.1s)\n',
      );
    });

    test('several runs are separated by one blank line', () {
      final output = _render([
        _report(entry: EntryKind.prePush, label: 'a'),
        _report(entry: EntryKind.prePush, label: 'b'),
      ]);

      expect(
        output,
        'stagelatch pre-push a: 1 file\n'
        '\n'
        '0 errors, 0 warnings. Push allowed. (0.1s)\n'
        '\n'
        'stagelatch pre-push b: 1 file\n'
        '\n'
        '0 errors, 0 warnings. Push allowed. (0.1s)\n',
      );
    });

    test('no run at all says there was nothing to check', () {
      expect(_render(const []), 'stagelatch: nothing to check.\n');
    });

    test('never prints two blank lines in a row', () {
      expect(_render([_blocked]), isNot(contains('\n\n\n')));
      expect(_render([_blocked]), endsWith('s)\n'));
    });
  });

  group('color', () {
    test('marks severities and rule ids, and changes no text', () {
      final colored = _render([_blocked], color: true);
      final stripped = colored.replaceAll(RegExp(r'\u001b\[[0-9;]*m'), '');

      expect(colored, contains('\u001b[31merror\u001b[0m'));
      expect(colored, contains('\u001b[2mpubspec/path-dependency\u001b[0m'));
      expect(stripped, _golden('blocked'));
    });

    test('warnings are yellow', () {
      final colored = _render([
        _report(
          findings: [
            _finding(
              'a.dart',
              1,
              1,
              'analyze/x',
              'm',
              severity: Severity.warning,
            ),
          ],
        ),
      ], color: true);

      expect(colored, contains('\u001b[33mwarning\u001b[0m'));
    });

    test('without color there is no escape sequence at all', () {
      expect(_render([_blocked]), isNot(contains('\u001b')));
    });
  });

  group('repository content is sanitized (security rule S5)', () {
    test('a path with an escape sequence cannot reach the terminal', () {
      final output = _render([
        _report(
          findings: [
            Finding(
              rule: const RuleId('analyze', 'x'),
              severity: Severity.error,
              message: 'first line\nsecond \u001b[2Jline',
              location: Location.wholeFile(RepoPath('evil\u001b[2Jname.dart')),
            ),
          ],
        ),
      ]);

      expect(output, isNot(contains('\u001b')));
      expect(output, contains('evil[2Jname.dart:1:1  error  analyze/x\n'));
      expect(output, contains('  first line second [2Jline\n'));
    });

    test('a branch name and a notice are sanitized too', () {
      final output = _render([
        _report(
          entry: EntryKind.prePush,
          label: 'feat\u001b[31m',
          notices: ['note with \u0007 bell'],
        ),
      ]);

      expect(output, isNot(contains('\u001b')));
      expect(output, isNot(contains('\u0007')));
      expect(output, startsWith('stagelatch pre-push feat[31m: 1 file\n'));
    });
  });
}

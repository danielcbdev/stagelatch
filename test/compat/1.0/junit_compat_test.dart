import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/reporters/junit_reporter.dart';
import 'package:test/test.dart';

import 'fixtures_path.dart';

CheckTiming _timing(String id, int ms, {int errors = 0, int warnings = 0}) =>
    CheckTiming(
      id: id,
      duration: Duration(milliseconds: ms),
      errors: errors,
      warnings: warnings,
      fixed: 0,
    );

void main() {
  test('JUnit reporter matches the frozen 1.0 fixture', () {
    final out = StringBuffer();
    JunitReporter(out).report([
      RunReport(
        entry: EntryKind.ci,
        label: 'HEAD',
        files: 1,
        verdict: Verdict.fail,
        findings: [
          Finding(
            rule: RuleId.parse('format/unformatted'),
            severity: Severity.warning,
            message: 'File is not formatted.',
            location: Location(
              RepoPath('lib/a.dart'),
              const Position(1, 1),
              const Position(1, 1),
            ),
          ),
          Finding(
            rule: RuleId.parse('pubspec/path-dependency'),
            severity: Severity.error,
            message:
                'Dependency "design_system" uses a path that is not a package '
                'in this repository: ../design_system.',
            location: Location(
              RepoPath('pubspec.yaml'),
              const Position(14, 5),
              const Position(14, 5),
            ),
          ),
        ],
        fixes: const [],
        timings: [
          _timing('format', 100, warnings: 1),
          _timing('pubspec', 234, errors: 1),
          _timing('sensitive-files', 50),
        ],
        total: const Duration(milliseconds: 384),
        timeBudget: const Duration(seconds: 2),
        budgetExceeded: false,
        suppressed: 0,
        baselined: 0,
        notices: const [],
      ),
    ]);

    expect(out.toString(), readCompatFixture('report.xml'));
  });
}

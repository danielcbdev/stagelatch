import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/checks/format/format_check.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/reporters/sarif_reporter.dart';
import 'package:test/test.dart';

import 'fixtures_path.dart';

RuleDescriptor? _describe(RuleId id) {
  for (final descriptor in [
    ...const FormatCheck().rules,
    ...pubspecRuleDescriptors,
  ]) {
    if (descriptor.id == id) return descriptor;
  }
  return null;
}

void main() {
  test('SARIF reporter matches the frozen 1.0 fixture', () {
    final out = StringBuffer();
    SarifReporter(out, toolVersion: '0.1.0', describe: _describe).report([
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
              const Position(1, 5),
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
              const Position(14, 26),
            ),
          ),
        ],
        fixes: const [],
        timings: const [],
        total: const Duration(milliseconds: 120),
        timeBudget: const Duration(seconds: 2),
        budgetExceeded: false,
        suppressed: 0,
        baselined: 0,
        notices: const [],
      ),
    ]);

    expect(out.toString(), readCompatFixture('report.sarif'));
  });
}

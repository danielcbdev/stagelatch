import 'dart:convert';

import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/reporters/json_reporter.dart';
import 'package:test/test.dart';

import 'fixtures_path.dart';

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

String _withoutDurations(String json) {
  Object? strip(Object? value) => switch (value) {
    final Map<String, Object?> map => {
      for (final entry in map.entries)
        if (entry.key != 'durationMs') entry.key: strip(entry.value),
    },
    final List<Object?> list => [for (final item in list) strip(item)],
    _ => value,
  };
  return jsonEncode(strip(jsonDecode(json)));
}

void main() {
  test('JSON report shape matches the frozen 1.0 fixture after stripping '
      'durations', () {
    final out = StringBuffer();
    JsonReporter(out, toolVersion: '0.1.0').report([
      RunReport(
        entry: EntryKind.preCommit,
        label: 'index',
        files: 4,
        verdict: Verdict.fail,
        findings: [
          Finding(
            rule: RuleId.parse('pubspec/path-dependency'),
            severity: Severity.error,
            message:
                'Dependency "design_system" uses a path that is not a '
                'package in this repository: ../design_system.',
            location: Location(
              RepoPath('pubspec.yaml'),
              const Position(14, 5),
              const Position(14, 26),
            ),
          ),
        ],
        fixes: [
          AppliedFix(
            rule: const RuleId('format', 'unformatted'),
            path: RepoPath('lib/checkout/cart.dart'),
            worktreeUpdated: false,
          ),
        ],
        timings: [
          CheckTiming(
            id: 'format',
            duration: _ms(41),
            errors: 0,
            warnings: 0,
            fixed: 1,
          ),
          CheckTiming(
            id: 'pubspec',
            duration: _ms(6),
            errors: 1,
            warnings: 0,
            fixed: 0,
          ),
        ],
        total: _ms(917),
        timeBudget: const Duration(seconds: 2),
        budgetExceeded: false,
        suppressed: 0,
        baselined: 0,
        notices: const [],
      ),
    ]);

    expect(
      _withoutDurations(out.toString()),
      _withoutDurations(readCompatFixture('json_report.json')),
    );

    final decoded = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(decoded['schemaVersion'], jsonSchemaVersion);
    expect(decoded['schemaVersion'], 1);
  });
}

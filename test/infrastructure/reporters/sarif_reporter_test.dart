import 'dart:io';

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

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

RunReport _report({List<Finding> findings = const [], int totalMs = 120}) =>
    RunReport(
      entry: EntryKind.ci,
      label: 'HEAD',
      files: findings.isEmpty ? 0 : 1,
      verdict: findings.any((finding) => finding.severity == Severity.error)
          ? Verdict.fail
          : Verdict.pass,
      findings: findings,
      fixes: const [],
      timings: const [],
      total: _ms(totalMs),
      timeBudget: const Duration(seconds: 2),
      budgetExceeded: false,
      suppressed: 0,
      baselined: 0,
      notices: const [],
    );

Finding _finding({
  required String rule,
  required String path,
  required Severity severity,
  required String message,
  int line = 1,
  int column = 1,
  int endLine = 1,
  int endColumn = 1,
}) => Finding(
  rule: RuleId.parse(rule),
  severity: severity,
  message: message,
  location: Location(
    RepoPath(path),
    Position(line, column),
    Position(endLine, endColumn),
  ),
);

/// Summaries for the rules the goldens use; unknown ids return null.
RuleDescriptor? _describe(RuleId id) {
  for (final descriptor in [
    ...const FormatCheck().rules,
    ...pubspecRuleDescriptors,
  ]) {
    if (descriptor.id == id) return descriptor;
  }
  return null;
}

String _render(List<RunReport> runs) {
  final out = StringBuffer();
  SarifReporter(out, toolVersion: '0.1.0', describe: _describe).report(runs);
  return out.toString();
}

String _golden(String name) =>
    File('test/goldens/sarif/$name.sarif').readAsStringSync();

List<Finding> _findingsFixture() => [
  _finding(
    rule: 'format/unformatted',
    path: 'lib/a.dart',
    severity: Severity.warning,
    message: 'File is not formatted.',
    endColumn: 5,
  ),
  _finding(
    rule: 'pubspec/path-dependency',
    path: 'pubspec.yaml',
    severity: Severity.error,
    message:
        'Dependency "design_system" uses a path that is not a package in '
        'this repository: ../design_system.',
    line: 14,
    column: 5,
    endLine: 14,
    endColumn: 26,
  ),
];

void main() {
  test('matches the golden: version 2.1.0, one run, the driver name, version '
      'and the schema', () {
    expect(
      _render([_report(findings: _findingsFixture())]),
      _golden('findings'),
    );
  });

  test('rules lists each rule that produced a result, once, sorted by id', () {
    final rendered = _render([
      _report(
        findings: [
          ..._findingsFixture(),
          _finding(
            rule: 'pubspec/path-dependency',
            path: 'pubspec.yaml',
            severity: Severity.error,
            message: 'second hit',
            line: 20,
            endLine: 20,
            endColumn: 2,
          ),
        ],
      ),
    ]);

    expect(
      rendered,
      contains(
        '"rules": [\n'
        '            {\n'
        '              "id": "format/unformatted",',
      ),
    );
    expect(
      rendered.indexOf('"id": "format/unformatted"'),
      lessThan(rendered.indexOf('"id": "pubspec/path-dependency"')),
    );
    expect('"id": "pubspec/path-dependency"'.allMatches(rendered).length, 1);
  });

  test('levels map from severity and regions are 1-based with an exclusive '
      'end column', () {
    final rendered = _render([_report(findings: _findingsFixture())]);

    expect(rendered, contains('"level": "warning"'));
    expect(rendered, contains('"level": "error"'));
    expect(
      rendered,
      contains(
        '"region": {\n'
        '                  "startLine": 1,\n'
        '                  "startColumn": 1,\n'
        '                  "endLine": 1,\n'
        '                  "endColumn": 5',
      ),
    );
    expect(
      rendered,
      contains(
        '"startLine": 14,\n'
        '                  "startColumn": 5,\n'
        '                  "endLine": 14,\n'
        '                  "endColumn": 26',
      ),
    );
  });

  test('an analyzer rule no check declares uses the rule id as its short '
      'description', () {
    expect(
      _render([
        _report(
          findings: [
            _finding(
              rule: 'analyze/unused_import',
              path: 'lib/main.dart',
              severity: Severity.error,
              message: "Unused import: 'dart:io'.",
              column: 8,
              endColumn: 17,
            ),
          ],
        ),
      ]),
      _golden('analyzer_rule'),
    );
  });

  test('a path with a space and non-ASCII characters is percent-encoded per '
      'segment', () {
    expect(
      _render([
        _report(
          findings: [
            _finding(
              rule: 'format/unformatted',
              path: 'docs/café menu/a.dart',
              severity: Severity.error,
              message: 'File is not formatted.',
            ),
          ],
        ),
      ]),
      _golden('unicode_path'),
    );
  });

  test('no run gives a valid document with no results', () {
    expect(_render(const []), _golden('clean'));
  });

  test('more than one run is an ArgumentError', () {
    expect(
      () => _render([_report(), _report()]),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('one run'),
        ),
      ),
    );
  });
}

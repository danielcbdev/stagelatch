import 'dart:io';

import 'package:stagelatch/src/application/pipeline/inline_ignore.dart';
import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/reporters/junit_reporter.dart';
import 'package:test/test.dart';

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

CheckTiming _timing(String id, int ms, {int errors = 0, int warnings = 0}) =>
    CheckTiming(
      id: id,
      duration: _ms(ms),
      errors: errors,
      warnings: warnings,
      fixed: 0,
    );

RunReport _report({
  List<Finding> findings = const [],
  List<CheckTiming> timings = const [],
  int totalMs = 0,
}) => RunReport(
  entry: EntryKind.ci,
  label: 'HEAD',
  files: findings.isEmpty ? 0 : 1,
  verdict: findings.any((finding) => finding.severity == Severity.error)
      ? Verdict.fail
      : Verdict.pass,
  findings: findings,
  fixes: const [],
  timings: timings,
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
}) => Finding(
  rule: RuleId.parse(rule),
  severity: severity,
  message: message,
  location: Location(
    RepoPath(path),
    Position(line, column),
    Position(line, column),
  ),
);

String _render(List<RunReport> runs) {
  final out = StringBuffer();
  JunitReporter(out).report(runs);
  return out.toString();
}

String _golden(String name) =>
    File('test/goldens/junit/$name.xml').readAsStringSync();

List<CheckTiming> get _threeChecks => [
  _timing('format', 100, warnings: 1),
  _timing('pubspec', 234, errors: 1),
  _timing('sensitive-files', 50),
];

List<Finding> get _findingsFixture => [
  _finding(
    rule: 'format/unformatted',
    path: 'lib/a.dart',
    severity: Severity.warning,
    message: 'File is not formatted.',
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
  ),
];

/// Minimal well-formedness check: stack of elements, entity decode of text.
({Map<String, String> attrs, List<({String name, String text})> failures})
_parseTestsuite(String xml) {
  expect(xml, endsWith('\n'));
  expect(xml, startsWith('<testsuite '));
  final suiteMatch = RegExp(r'^<testsuite\b([^>]*)>([\s\S]*)</testsuite>\n$')
      .firstMatch(xml);
  expect(suiteMatch, isNotNull, reason: 'document is not a single testsuite');
  final attrs = _attributes(suiteMatch!.group(1)!);
  final body = suiteMatch.group(2)!;
  final failures = <({String name, String text})>[];
  final caseRe = RegExp(r'<testcase\b([^>]*)(?:/>|>([\s\S]*?)</testcase>)');
  for (final match in caseRe.allMatches(body)) {
    final inner = match.group(2);
    if (inner == null) continue;
    for (final failure in RegExp(
      r'<failure\b([^>]*)>([\s\S]*?)</failure>',
    ).allMatches(inner)) {
      failures.add((
        name: _unescape(_attributes(failure.group(1)!)['message'] ?? ''),
        text: _unescape(failure.group(2)!),
      ));
    }
  }
  return (attrs: attrs, failures: failures);
}

Map<String, String> _attributes(String raw) {
  final attrs = <String, String>{};
  for (final match in RegExp(
    r'''([A-Za-z_:][\w:.-]*)="([^"]*)"''',
  ).allMatches(raw)) {
    attrs[match.group(1)!] = match.group(2)!;
  }
  return attrs;
}

String _unescape(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

void main() {
  test('one testcase per check that ran; error findings are failures; '
      'warnings go to system-out', () {
    expect(
      _render([
        _report(
          findings: _findingsFixture,
          timings: _threeChecks,
          totalMs: 384,
        ),
      ]),
      _golden('findings'),
    );
  });

  test('the testsuite counts checks and failed checks: tests="3" '
      'failures="1" errors="0"', () {
    final parsed = _parseTestsuite(
      _render([
        _report(
          findings: _findingsFixture,
          timings: _threeChecks,
          totalMs: 384,
        ),
      ]),
    );
    expect(parsed.attrs['tests'], '3');
    expect(parsed.attrs['failures'], '1');
    expect(parsed.attrs['errors'], '0');
  });

  test('a check with two error findings is one failed testcase with two '
      'failure elements', () {
    final rendered = _render([
      _report(
        findings: [
          _finding(
            rule: 'pubspec/path-dependency',
            path: 'pubspec.yaml',
            severity: Severity.error,
            message: 'first',
            line: 10,
          ),
          _finding(
            rule: 'pubspec/dependency-overrides',
            path: 'pubspec.yaml',
            severity: Severity.error,
            message: 'second',
            line: 20,
            column: 3,
          ),
        ],
        timings: [_timing('pubspec', 10, errors: 2)],
        totalMs: 10,
      ),
    ]);
    expect('<testcase '.allMatches(rendered).length, 1);
    expect('<failure '.allMatches(rendered).length, 2);
    expect(rendered, contains('message="pubspec/path-dependency: first"'));
    expect(
      rendered,
      contains('message="pubspec/dependency-overrides: second"'),
    );
    expect(rendered, contains('>pubspec.yaml:10:1</failure>'));
    expect(rendered, contains('>pubspec.yaml:20:3</failure>'));
    expect(parsedFailures(rendered), '1');
  });

  test('a stagelatch/invalid-ignore finding goes to an extra last testcase '
      'named stagelatch', () {
    expect(
      _render([
        _report(
          findings: [
            _finding(
              rule: invalidIgnoreRule.toString(),
              path: 'lib/a.dart',
              severity: Severity.warning,
              message: 'Unknown rule "foo/bar" in stagelatch:ignore.',
              column: 4,
            ),
          ],
          timings: [_timing('format', 100)],
          totalMs: 100,
        ),
      ]),
      _golden('invalid_ignore'),
    );
    expect(
      _render([
        _report(
          findings: _findingsFixture,
          timings: _threeChecks,
          totalMs: 384,
        ),
      ]),
      isNot(contains('classname="stagelatch" name="stagelatch"')),
    );
  });

  test('a message containing ]]> or markup cannot break the document', () {
    const message = 'before ]]> <failure> & "quote" after';
    final rendered = _render([
      _report(
        findings: [
          _finding(
            rule: 'pubspec/path-dependency',
            path: 'lib/<evil>.dart',
            severity: Severity.error,
            message: message,
          ),
        ],
        timings: [_timing('pubspec', 1, errors: 1)],
        totalMs: 1,
      ),
    ]);
    final parsed = _parseTestsuite(rendered);
    expect(parsed.failures, hasLength(1));
    expect(parsed.failures.single.name, 'pubspec/path-dependency: $message');
    expect(parsed.failures.single.text, 'lib/<evil>.dart:1:1');
    expect(rendered, isNot(contains(']]>')));
    expect(rendered, contains('&lt;failure&gt;'));
  });

  test('time has three decimals', () {
    final rendered = _render([
      _report(timings: [_timing('format', 1234)], totalMs: 1234),
    ]);
    expect(rendered, contains('time="1.234"'));
  });

  test('no run gives a valid empty testsuite', () {
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

String parsedFailures(String rendered) =>
    _parseTestsuite(rendered).attrs['failures']!;

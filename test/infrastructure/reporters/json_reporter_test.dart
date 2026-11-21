import 'dart:convert';
import 'dart:io';

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

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

RunReport _report({
  EntryKind entry = EntryKind.preCommit,
  int files = 1,
  bool all = false,
  List<Finding> findings = const [],
  List<AppliedFix> fixes = const [],
  List<CheckTiming> timings = const [],
  int totalMs = 120,
  bool budgetExceeded = false,
  int suppressed = 0,
  List<String> notices = const [],
}) => RunReport(
  entry: entry,
  label: 'index',
  files: files,
  all: all,
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
  baselined: 0,
  notices: notices,
);

Finding _finding(
  String rule,
  String path,
  int line,
  int column,
  int endColumn,
  String message,
) => Finding(
  rule: RuleId.parse(rule),
  severity: Severity.error,
  message: message,
  location: Location(
    RepoPath(path),
    Position(line, column),
    Position(line, endColumn),
  ),
);

RunReport _single({int formatMs = 41, int pubspecMs = 6, int totalMs = 917}) =>
    _report(
      files: 4,
      totalMs: totalMs,
      findings: [
        _finding(
          'pubspec/path-dependency',
          'pubspec.yaml',
          14,
          5,
          26,
          'Dependency "design_system" uses a path that is not a package in '
              'this repository: ../design_system.',
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
          duration: _ms(formatMs),
          errors: 0,
          warnings: 0,
          fixed: 1,
        ),
        CheckTiming(
          id: 'pubspec',
          duration: _ms(pubspecMs),
          errors: 1,
          warnings: 0,
          fixed: 0,
        ),
      ],
    );

String _render(List<RunReport> runs) {
  final out = StringBuffer();
  JsonReporter(out, toolVersion: '0.1.0').report(runs);
  return out.toString();
}

String _golden(String name) =>
    File('test/goldens/json/$name.json').readAsStringSync();

/// [json] with every `durationMs` field removed, re-encoded.
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
  test('one run renders the object of specs/cli.md section 5, keys in '
      'order', () {
    expect(_render([_single()]), _golden('single'));
  });

  test('"all" follows "files" and says whether the run used --all', () {
    final plain = _render([_report()]);
    final all = _render([_report(all: true)]);

    expect(plain, contains('"files": 1,\n  "all": false,\n'));
    expect(all, contains('"files": 1,\n  "all": true,\n'));
  });

  test('several runs render a "runs" array with a top-level verdict and '
      'exit code', () {
    final rendered = _render([
      _report(entry: EntryKind.prePush),
      _report(
        entry: EntryKind.prePush,
        files: 2,
        totalMs: 2500,
        budgetExceeded: true,
        suppressed: 1,
        notices: ['a notice'],
        findings: [
          _finding(
            'pubspec/dependency-overrides',
            'pubspec.yaml',
            3,
            1,
            2,
            'x',
          ),
        ],
      ),
    ]);

    expect(rendered, _golden('multi'));
  });

  test('no run at all renders an empty "runs" array that passes', () {
    final decoded = jsonDecode(_render(const [])) as Map<String, Object?>;

    expect(decoded['runs'], isEmpty);
    expect(decoded['verdict'], 'pass');
    expect(decoded['exitCode'], 0);
  });

  test('output is identical across runs after removing durationMs', () {
    final first = _render([_single()]);
    final second = _render([
      _single(formatMs: 400, pubspecMs: 9, totalMs: 3000),
    ]);

    expect(first, isNot(second));
    expect(_withoutDurations(first), _withoutDurations(second));
  });

  test('strings are encoded by the JSON encoder, never concatenated', () {
    const message = 'quote " backslash \\ newline \n tab \t end';
    final rendered = _render([
      _report(findings: [_finding('a/b', 'x "y".yaml', 1, 1, 2, message)]),
    ]);
    final finding =
        ((jsonDecode(rendered) as Map<String, Object?>)['findings']!
                    as List<Object?>)
                .single!
            as Map<String, Object?>;

    expect(finding['message'], message);
    expect(finding['path'], 'x "y".yaml');
  });

  test('the error object is compact and names the kind', () {
    expect(
      renderErrorJson(
        kind: 'usage',
        message: 'Unknown hook "x".',
        exitCode: 64,
      ),
      '{"schemaVersion":1,"error":{"kind":"usage","message":'
      r'"Unknown hook \"x\"."},"exitCode":64}',
    );
  });
}

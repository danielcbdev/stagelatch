import 'package:stagelatch/src/application/baseline/baseline.dart';
import 'package:stagelatch/src/application/baseline/baseline_filter.dart';
import 'package:stagelatch/src/application/baseline/fingerprint.dart';
import 'package:stagelatch/src/application/pipeline/inline_ignore.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_snapshot_files.dart';

Finding _finding(
  String path,
  int line, {
  String rule = 'analyze/unused_import',
  String message = 'm',
}) => Finding(
  rule: RuleId.parse(rule),
  severity: Severity.error,
  message: message,
  location: Location(RepoPath(path), Position(line, 1), Position(line, 5)),
);

Future<BaselineEntry> _entryFor(
  Finding finding,
  FakeSnapshotFiles snapshot,
  int count,
) async => BaselineEntry(
  rule: finding.rule,
  path: finding.location.path,
  fingerprint: await fingerprintOf(finding, snapshot),
  count: count,
);

void main() {
  final snapshot = FakeSnapshotFiles({
    'lib/a.dart': 'bad;\nbad;\nbad;\nother;\n',
    'lib/b.dart': 'bad;\n',
  });

  test('an empty baseline keeps everything', () async {
    final findings = [_finding('lib/a.dart', 1)];

    final outcome = await applyBaseline(findings, Baseline.empty, snapshot);

    expect(outcome.kept, findings);
    expect(outcome.baselined, 0);
  });

  test('counts are consumed in finding order', () async {
    final findings = [
      _finding('lib/a.dart', 1),
      _finding('lib/a.dart', 2),
      _finding('lib/a.dart', 3),
    ];
    final baseline = Baseline([await _entryFor(findings.first, snapshot, 2)]);

    final outcome = await applyBaseline(findings, baseline, snapshot);

    expect(outcome.baselined, 2);
    expect(outcome.kept, [findings.last]);
  });

  test('a finding with another snippet, path or rule is kept', () async {
    final accepted = _finding('lib/a.dart', 1);
    final baseline = Baseline([await _entryFor(accepted, snapshot, 5)]);
    final others = [
      _finding('lib/a.dart', 4),
      _finding('lib/b.dart', 1),
      _finding('lib/a.dart', 1, rule: 'analyze/dead_code'),
    ];

    final outcome = await applyBaseline(others, baseline, snapshot);

    expect(outcome.kept, others);
    expect(outcome.baselined, 0);
  });

  test('moving the finding to another line keeps it accepted', () async {
    final before = FakeSnapshotFiles({'lib/a.dart': 'bad;\n'});
    final after = FakeSnapshotFiles({'lib/a.dart': '1;\n2;\n3;\nbad;\n'});
    final baseline = Baseline([
      await _entryFor(_finding('lib/a.dart', 1), before, 1),
    ]);

    final outcome = await applyBaseline(
      [_finding('lib/a.dart', 4)],
      baseline,
      after,
    );

    expect(outcome.kept, isEmpty);
    expect(outcome.baselined, 1);
  });

  test('stagelatch/invalid-ignore is never baselined', () async {
    final ignore = _finding(
      'lib/a.dart',
      1,
      rule: invalidIgnoreRule.toString(),
    );
    final baseline = Baseline([await _entryFor(ignore, snapshot, 3)]);

    final outcome = await applyBaseline([ignore], baseline, snapshot);

    expect(outcome.kept, [ignore]);
    expect(outcome.baselined, 0);
  });

  test('counts go to the first findings in the order given', () async {
    final first = _finding('lib/a.dart', 1, message: 'first');
    final second = _finding('lib/a.dart', 1, message: 'second');
    final baseline = Baseline([await _entryFor(first, snapshot, 1)]);

    final outcome = await applyBaseline([first, second], baseline, snapshot);

    expect(outcome.kept, [second]);
  });
}

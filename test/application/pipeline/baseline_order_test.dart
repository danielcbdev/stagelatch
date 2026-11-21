import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/baseline/baseline.dart';
import 'package:stagelatch/src/application/baseline/baseline_codec.dart';
import 'package:stagelatch/src/application/baseline/fingerprint.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/pipeline.dart';
import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/working_tree.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_check.dart';
import '../../support/fake_clock.dart';
import '../../support/fake_dart_toolchain_factory.dart';
import '../../support/fake_git_repository.dart';
import '../../support/fake_sdk_locator.dart';
import '../../support/fake_snapshot_files.dart';
import '../../support/fake_test_runner.dart';
import '../../support/fake_working_tree.dart';

const _config =
    'hooks:\n  pre-commit: [alpha]\n  pre-push: [beta]\n  ci: [alpha, beta]\n';
const _content = 'bad;\nbad;\nbad;\n';
final RepoPath _baselinePath = RepoPath('.stagelatch/baseline.json');

Pipeline _pipeline(
  FakeGitRepository git,
  List<Check> checks, {
  WorkingTree? workingTree,
}) => Pipeline(
  git: git,
  configLoader: ConfigLoader(
    const StructuredDocuments(),
    workingTree ?? FakeWorkingTree(),
  ),
  // The config names `beta`, so it is always known, even when no test
  // gives it behavior.
  registry: CheckRegistry([
    ...checks,
    if (!checks.any((check) => check.id == 'beta')) FakeCheck('beta'),
  ]),
  documents: const StructuredDocuments(),
  clock: FakeClock(),
  toolVersion: Version.parse('0.1.0'),
  sdkLocator: FakeSdkLocator(),
  toolchains: FakeDartToolchainFactory(),
  testRunners: FakeTestRunnerFactory(FakeTestRunner()),
);

/// The baseline file that accepts [count] findings like [finding] in a file
/// whose text is [_content].
Future<String> _baselineFor(Finding finding, int count) async => encodeBaseline(
  Baseline([
    BaselineEntry(
      rule: finding.rule,
      path: finding.location.path,
      fingerprint: await fingerprintOf(
        finding,
        FakeSnapshotFiles({finding.location.path.value: _content}),
      ),
      count: count,
    ),
  ]),
);

Future<RunReport> _run(
  FakeGitRepository git,
  List<Check> checks, {
  RunRequest request = const RunRequest(entry: PreCommitEntry()),
}) async => (await _pipeline(git, checks).run(request)).single;

/// A check that reports one finding per line of `a.txt`, in [lines] order.
FakeCheck _alpha(List<int> lines) {
  late final FakeCheck check;
  return check = FakeCheck(
    'alpha',
    onRun: (_) async => CheckResult(
      findings: [for (final line in lines) check.finding('a.txt', line: line)],
    ),
  );
}

void main() {
  late FakeCheck alpha;

  setUp(() => alpha = _alpha([3, 1, 2]));

  test('counts are consumed in the global sort order, not the order the '
      'check reported', () async {
    final git = FakeGitRepository(
      index: {
        'stagelatch.yaml': _config,
        'a.txt': _content,
        _baselinePath.value: await _baselineFor(alpha.finding('a.txt'), 2),
      },
    );

    final report = await _run(git, [alpha]);

    expect(report.baselined, 2);
    expect(report.findings.map((finding) => finding.location.start.line), [3]);
  });

  test('the check table counts what is left after the baseline', () async {
    final git = FakeGitRepository(
      index: {
        'stagelatch.yaml': _config,
        'a.txt': _content,
        _baselinePath.value: await _baselineFor(alpha.finding('a.txt'), 3),
      },
    );

    final report = await _run(git, [alpha]);

    expect(report.findings, isEmpty);
    expect(report.verdict, Verdict.pass);
    expect(report.timings.single.errors, 0);
  });

  test(
    'the baseline is read from the snapshot, not the working tree',
    () async {
      final git = FakeGitRepository(
        index: {'stagelatch.yaml': _config, 'a.txt': _content},
      );
      final workingTree = FakeWorkingTree({
        _baselinePath.value: await _baselineFor(alpha.finding('a.txt'), 3),
      });

      final report = (await _pipeline(
        git,
        [alpha],
        workingTree: workingTree,
      ).run(const RunRequest(entry: PreCommitEntry()))).single;

      expect(report.baselined, 0);
      expect(report.findings, hasLength(3));
    },
  );

  test('useBaseline: false ignores the file', () async {
    final git = FakeGitRepository(
      index: {
        'stagelatch.yaml': _config,
        'a.txt': _content,
        _baselinePath.value: await _baselineFor(alpha.finding('a.txt'), 3),
      },
    );

    final report = await _run(git, [
      alpha,
    ], request: const RunRequest(entry: PreCommitEntry(), useBaseline: false));

    expect(report.baselined, 0);
    expect(report.findings, hasLength(3));
  });

  test('a malformed baseline is a config error naming the file', () async {
    final git = FakeGitRepository(
      index: {
        'stagelatch.yaml': _config,
        'a.txt': _content,
        _baselinePath.value: '{"version": 9}',
      },
    );

    expect(
      _run(git, [alpha]),
      throwsA(
        isA<ConfigException>().having(
          (error) => error.toString(),
          'message',
          startsWith('.stagelatch/baseline.json:1:1: Invalid baseline'),
        ),
      ),
    );
  });

  test('RunRequest.hook picks the selectors of another hook', () async {
    final beta = FakeCheck('beta');
    final git = FakeGitRepository(
      index: {'stagelatch.yaml': _config, 'a.txt': _content},
    );

    final report = await _run(git, [
      alpha,
      beta,
    ], request: const RunRequest(entry: PreCommitEntry(), hook: 'ci'));

    expect(report.timings.map((timing) => timing.id), ['alpha', 'beta']);
  });

  test('currentBaseline counts findings by rule, path and fingerprint and '
      'knows the baseline path', () async {
    final git = FakeGitRepository(
      index: {'stagelatch.yaml': _config, 'a.txt': _content},
    );

    final current = await _pipeline(git, [alpha]).currentBaseline(
      const RunRequest(entry: PreCommitEntry(), useBaseline: false),
    );

    expect(current.path, _baselinePath);
    expect(current.baseline.entries, hasLength(1));
    expect(current.baseline.entries.single.count, 3);
    expect(current.baseline.entries.single.rule, const RuleId('alpha', 'one'));
  });
}

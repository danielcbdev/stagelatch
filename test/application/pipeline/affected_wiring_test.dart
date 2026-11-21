import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/pipeline.dart';
import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/checks/tests/tests_check.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/dart/test_runner.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_clock.dart';
import '../../support/fake_dart_toolchain_factory.dart';
import '../../support/fake_git_repository.dart';
import '../../support/fake_sdk_locator.dart';
import '../../support/fake_test_runner.dart';
import '../../support/fake_working_tree.dart';

const _push = RunRequest(
  entry: PrePushEntry(remote: 'origin', refs: []),
);

/// A pushed commit with one package, one test, and a configuration that runs
/// `tests/affected` on pre-push, plus [more] configuration.
FakeGitRepository _git({String more = '', Set<String> diverging = const {}}) =>
    FakeGitRepository(
      commits: {
        'head': {
          'stagelatch.yaml':
              'hooks:\n  pre-commit: []\n  pre-push: [tests/affected]\n$more',
          'pubspec.yaml': 'name: app\n',
          'lib/a.dart': 'int a = 1;\n',
          'test/a_test.dart': "import '../lib/a.dart';\n",
        },
      },
      runs: [
        ResolvedRun(
          snapshot: const CommitSnapshot('head'),
          base: null,
          changes: ChangeSet([
            FileChange(path: RepoPath('lib/a.dart'), kind: ChangeKind.modified),
          ]),
          targetBranch: 'main',
          label: 'main',
        ),
      ],
      diverging: diverging,
    );

Future<(RunReport, FakeTestRunner, FakeTestRunnerFactory)> _run(
  FakeGitRepository git, {
  TestRunResult result = const TestRunResult(),
  RunRequest request = _push,
}) async {
  final runner = FakeTestRunner(fallback: result);
  final factory = FakeTestRunnerFactory(runner);
  final reports = await Pipeline(
    git: git,
    configLoader: ConfigLoader(const StructuredDocuments(), FakeWorkingTree()),
    registry: CheckRegistry(const [TestsCheck()]),
    documents: const StructuredDocuments(),
    clock: FakeClock(),
    toolVersion: Version.parse('0.3.0'),
    sdkLocator: FakeSdkLocator(),
    toolchains: FakeDartToolchainFactory(),
    testRunners: factory,
  ).run(request);
  return (reports.single, runner, factory);
}

final _failure = TestRunResult(
  failures: [
    FailedTest(
      file: RepoPath('test/a_test.dart'),
      line: 1,
      column: 1,
      name: 'a fails',
    ),
  ],
);

void main() {
  test('a pushed commit with a failing test blocks', () async {
    final (report, runner, _) = await _run(_git(), result: _failure);

    expect(runner.calls, hasLength(1));
    expect(report.verdict, Verdict.fail);
    expect(report.findings.single.message, 'Test failed: a fails.');
  });

  test('the divergence test is asked against the snapshot being judged, '
      'before and after the run', () async {
    final git = _git();

    await _run(git);

    expect(git.divergentCalls, hasLength(2));
    expect(git.divergentCalls.first, contains(RepoPath('test/a_test.dart')));
    expect(git.divergentCalls.first, contains(RepoPath('pubspec.yaml')));
  });

  test('a dirty skip is a warning and starts no process', () async {
    final (report, runner, factory) = await _run(
      _git(diverging: {'lib/a.dart'}),
      result: _failure,
    );

    expect(runner.calls, isEmpty);
    expect(factory.createCount, 0);
    expect(report.verdict, Verdict.pass);
    expect(report.findings.single.severity, Severity.warning);
  });

  test('rules: tests/affected: error does not raise a dirty skip', () async {
    final (report, runner, _) = await _run(
      _git(
        more: 'rules:\n  tests/affected: error\n',
        diverging: {'lib/a.dart'},
      ),
      result: _failure,
    );

    expect(runner.calls, isEmpty);
    expect(report.verdict, Verdict.pass);
    expect(report.findings.single.severity, Severity.warning);
  });

  test('rules: tests/affected: error still blocks a real failure', () async {
    final (report, _, _) = await _run(
      _git(more: 'rules:\n  tests/affected: error\n'),
      result: _failure,
    );

    expect(report.verdict, Verdict.fail);
    expect(report.findings.single.severity, Severity.error);
  });

  test('rules: tests/affected: warning lowers a failure but a skip stays a '
      'warning', () async {
    final (failed, _, _) = await _run(
      _git(more: 'rules:\n  tests/affected: warning\n'),
      result: _failure,
    );
    final (skipped, _, _) = await _run(
      _git(
        more: 'rules:\n  tests/affected: warning\n',
        diverging: {'lib/a.dart'},
      ),
    );

    expect(failed.verdict, Verdict.pass);
    expect(failed.findings.single.severity, Severity.warning);
    expect(skipped.findings.single.severity, Severity.warning);
  });

  test('rules: tests/affected: off drops a dirty skip', () async {
    final (report, runner, _) = await _run(
      _git(more: 'rules:\n  tests/affected: off\n', diverging: {'lib/a.dart'}),
    );

    expect(runner.calls, isEmpty);
    expect(report.findings, isEmpty);
  });

  test(
    'on pre-commit, even when listed, no runner is created and nothing runs',
    () async {
      final git = FakeGitRepository(
        index: {
          'stagelatch.yaml': 'hooks:\n  pre-commit: [tests/affected]\n',
          'pubspec.yaml': 'name: app\n',
          'test/a_test.dart': '',
        },
        changes: ChangeSet([
          FileChange(
            path: RepoPath('test/a_test.dart'),
            kind: ChangeKind.modified,
          ),
        ]),
      );

      final (report, runner, factory) = await _run(
        git,
        result: _failure,
        request: const RunRequest(entry: PreCommitEntry()),
      );

      expect(runner.calls, isEmpty);
      expect(factory.createCount, 0);
      expect(git.divergentCalls, isEmpty);
      expect(report.findings, isEmpty);
    },
  );
}

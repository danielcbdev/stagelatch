import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/pipeline.dart';
import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/fix.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_check.dart';
import '../../support/fake_clock.dart';
import '../../support/fake_dart_toolchain_factory.dart';
import '../../support/fake_git_repository.dart';
import '../../support/fake_sdk_locator.dart';
import '../../support/fake_test_runner.dart';
import '../../support/fake_working_tree.dart';

const _preCommit = RunRequest(entry: PreCommitEntry());

String _config(List<String> selectors) =>
    'hooks:\n  pre-commit: [${selectors.join(', ')}]\n';

void main() {
  late FakeDartToolchainFactory factory;
  late FakeSdkLocator locator;

  setUp(() {
    factory = FakeDartToolchainFactory();
    locator = FakeSdkLocator();
  });

  Future<RunReport> run(FakeGitRepository git, List<Check> checks) async =>
      (await Pipeline(
        git: git,
        configLoader: ConfigLoader(
          const StructuredDocuments(),
          FakeWorkingTree(),
        ),
        registry: CheckRegistry(checks),
        documents: const StructuredDocuments(),
        clock: FakeClock(),
        toolVersion: Version.parse('0.1.0'),
        sdkLocator: locator,
        toolchains: factory,
        testRunners: FakeTestRunnerFactory(FakeTestRunner()),
      ).run(_preCommit)).single;

  FakeCheck usingDart(String id, {CheckPhase phase = CheckPhase.verify}) =>
      FakeCheck(
        id,
        phase: phase,
        onRun: (context) async {
          await context.dart.format(RepoPath('lib/a.dart'), 'x');
          return const CheckResult();
        },
      );

  test('the toolchain is not created when no check asks for it', () async {
    await run(
      FakeGitRepository(
        index: {
          'stagelatch.yaml': _config(['alpha']),
        },
      ),
      [FakeCheck('alpha')],
    );

    expect(factory.createCount, 0);
    expect(locator.calls, 0);
  });

  test('concurrent verify checks share one toolchain', () async {
    await run(
      FakeGitRepository(
        index: {
          'stagelatch.yaml': _config(['alpha', 'beta']),
        },
      ),
      [usingDart('alpha'), usingDart('beta')],
    );

    expect(factory.createCount, 1);
    expect(locator.calls, 1);
  });

  test('the fix phase and the verify phase get separate toolchains, the '
      'second over the fixed index', () async {
    late final FakeCheck fixer;
    fixer = FakeCheck(
      'fixer',
      phase: CheckPhase.fix,
      onRun: (context) async {
        await context.dart.format(RepoPath('lib/a.dart'), 'x');
        return CheckResult(
          findings: [fixer.finding('lib/a.dart')],
          fixes: [
            Fix(
              rule: const RuleId('fixer', 'one'),
              path: RepoPath('lib/a.dart'),
              content: 'fixed\n',
            ),
          ],
        );
      },
    );

    await run(
      FakeGitRepository(
        index: {
          'stagelatch.yaml': _config(['fixer', 'beta']),
          'lib/a.dart': 'x\n',
        },
      ),
      [fixer, usingDart('beta')],
    );

    expect(factory.createCount, 2);
    expect(
      await factory.snapshots.last.readText(RepoPath('lib/a.dart')),
      'fixed\n',
    );
  });

  test('every toolchain is closed, even when a check throws', () async {
    final boom = FakeCheck(
      'boom',
      onRun: (context) async {
        await context.dart.format(RepoPath('lib/a.dart'), 'x');
        throw StateError('nope');
      },
    );

    await expectLater(
      run(
        FakeGitRepository(
          index: {
            'stagelatch.yaml': _config(['boom']),
          },
        ),
        [boom],
      ),
      throwsA(isA<InternalException>()),
    );
    expect(factory.created.single.closed, isTrue);
  });

  test('packages come from the snapshot, and the import graph from facts '
      'of every .dart file', () async {
    late Set<RepoPath> dependents;
    late String? package;
    final probe = FakeCheck(
      'probe',
      onRun: (context) async {
        package = context.packages
            .packageOf(RepoPath('packages/ui/lib/b.dart'))
            ?.name;
        dependents = (await context.importGraph).dependentsOf({
          RepoPath('packages/ui/lib/b.dart'),
        });
        return const CheckResult();
      },
    );

    await run(
      FakeGitRepository(
        index: {
          'stagelatch.yaml': _config(['probe']),
          'pubspec.yaml': 'name: app\n',
          'lib/a.dart': "import 'package:ui/b.dart';\n",
          'packages/ui/pubspec.yaml': 'name: ui\n',
          'packages/ui/lib/b.dart': '',
        },
        changes: ChangeSet([
          FileChange(path: RepoPath('lib/a.dart'), kind: ChangeKind.added),
        ]),
      ),
      [probe],
    );

    expect(package, 'ui');
    expect(dependents, {
      RepoPath('lib/a.dart'),
      RepoPath('packages/ui/lib/b.dart'),
    });
    expect(factory.createCount, 1);
  });

  test('an SDK that cannot be found fails the run with its message', () async {
    locator = FakeSdkLocator(
      error: const ConfigException(
        'No Dart SDK found. Install Dart or set sdk_path.',
      ),
    );

    await expectLater(
      run(
        FakeGitRepository(
          index: {
            'stagelatch.yaml': _config(['alpha']),
          },
        ),
        [usingDart('alpha')],
      ),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          'No Dart SDK found. Install Dart or set sdk_path.',
        ),
      ),
    );
  });
}

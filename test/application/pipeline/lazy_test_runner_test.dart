import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/lazy_test_runner.dart';
import 'package:stagelatch/src/domain/dart/test_runner.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_sdk_locator.dart';
import '../../support/fake_snapshot_files.dart';
import '../../support/fake_test_runner.dart';
import '../../support/fake_working_tree.dart';

const _package = DartPackage(root: null, name: 'app');

Future<Config> _config() async =>
    (await ConfigLoader(const StructuredDocuments(), FakeWorkingTree()).load(
      FakeSnapshotFiles(const {}),
      toolVersion: Version.parse('0.3.0'),
      catalog: CheckRegistry(const []),
    )).config;

void main() {
  late FakeSdkLocator locator;
  late FakeTestRunner runner;
  late FakeTestRunnerFactory factory;
  late LazyTestRunner lazy;

  setUp(() async {
    locator = FakeSdkLocator();
    runner = FakeTestRunner();
    factory = FakeTestRunnerFactory(runner);
    lazy = LazyTestRunner(
      locator: locator,
      factory: factory,
      config: await _config(),
      repoRoot: () async => '/repo',
    );
  });

  test('the SDK is not located until a run is asked for', () async {
    expect(locator.calls, 0);
    expect(factory.createCount, 0);

    await lazy.run(_package, [RepoPath('test/a_test.dart')]);

    expect(locator.calls, 1);
    expect(factory.createCount, 1);
    expect(factory.repoRoots, ['/repo']);
    expect(runner.calls.single.files, [RepoPath('test/a_test.dart')]);
  });

  test('the runner is created once for several runs', () async {
    await lazy.run(_package, [RepoPath('test/a_test.dart')]);
    await lazy.run(_package, [RepoPath('test/b_test.dart')]);
    await Future.wait([
      lazy.run(_package, [RepoPath('test/c_test.dart')]),
      lazy.run(_package, [RepoPath('test/d_test.dart')]),
    ]);

    expect(locator.calls, 1);
    expect(factory.createCount, 1);
    expect(runner.calls, hasLength(4));
  });

  test('the result of the runner is returned unchanged', () async {
    const result = TestRunResult(startupError: 'boom');
    lazy = LazyTestRunner(
      locator: locator,
      factory: FakeTestRunnerFactory(FakeTestRunner(fallback: result)),
      config: await _config(),
      repoRoot: () async => '/repo',
    );

    expect(await lazy.run(_package, [RepoPath('test/a_test.dart')]), result);
  });

  test('an SDK that cannot be located is the error of the run', () async {
    locator = FakeSdkLocator(error: const ConfigException('no sdk'));
    lazy = LazyTestRunner(
      locator: locator,
      factory: factory,
      config: await _config(),
      repoRoot: () async => '/repo',
    );

    await expectLater(
      lazy.run(_package, [RepoPath('test/a_test.dart')]),
      throwsA(isA<ConfigException>()),
    );
    expect(factory.createCount, 0);
  });
}

import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/application/why/why.dart';
import 'package:stagelatch/src/checks/tests/tests_check.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_dart_toolchain_factory.dart';
import '../../support/fake_git_repository.dart';
import '../../support/fake_sdk_locator.dart';
import '../../support/fake_working_tree.dart';

const _app = DartPackage(root: null, name: 'app');

WhyChain _chain(WhyOrigin origin, List<String> files, {DartPackage? package}) =>
    WhyChain(
      origin: origin,
      files: [for (final path in files) RepoPath(path)],
      package: package,
    );

WhyResult _result(String test, List<WhyChain> chains) =>
    WhyResult(test: RepoPath(test), chains: chains);

Why _why({
  required Map<String, Object> index,
  required ChangeSet changes,
  FakeDartToolchainFactory? factory,
}) {
  final git = FakeGitRepository(
    index: index,
    changes: changes,
    againstIndex: ResolvedRun(
      snapshot: const IndexSnapshot(),
      base: const CommitSnapshot('base'),
      changes: changes,
      targetBranch: 'main',
      label: 'index',
    ),
  );
  return Why(
    git: git,
    configLoader: ConfigLoader(const StructuredDocuments(), FakeWorkingTree()),
    registry: CheckRegistry([const TestsCheck()]),
    documents: const StructuredDocuments(),
    sdkLocator: FakeSdkLocator(),
    toolchains: factory ?? FakeDartToolchainFactory(),
    toolVersion: Version.parse('0.2.0'),
  );
}

Map<String, Object> get _cartIndex => {
  'pubspec.yaml': 'name: app\n',
  'lib/checkout/cart.dart': 'class Cart {}\n',
  'lib/checkout/cart_controller.dart':
      "import 'cart.dart';\nclass CartController {}\n",
  'test/checkout/cart_test.dart':
      "import 'package:app/checkout/cart_controller.dart';\n"
      'void main() {}\n',
};

void main() {
  test('prints one shortest chain per changed file that reaches the test', () {
    final result = _result('test/checkout/cart_test.dart', [
      _chain(WhyOrigin.changed, [
        'lib/checkout/cart.dart',
        'lib/checkout/cart_controller.dart',
        'test/checkout/cart_test.dart',
      ]),
    ]);

    expect(renderWhy(result), '''
test/checkout/cart_test.dart is affected by 1 changed file:

lib/checkout/cart.dart (changed)
  imported by lib/checkout/cart_controller.dart
  imported by test/checkout/cart_test.dart
''');
  });

  test('the header counts changed files: 2 changed files', () {
    final result = _result('test/a_test.dart', [
      _chain(WhyOrigin.changed, ['lib/a.dart', 'test/a_test.dart']),
      _chain(WhyOrigin.changed, ['lib/b.dart', 'test/a_test.dart']),
    ]);

    expect(
      renderWhy(result),
      startsWith('test/a_test.dart is affected by 2 changed files:\n'),
    );
  });

  test('chains are in path order of the changed files', () async {
    final why = _why(
      index: {
        'pubspec.yaml': 'name: app\n',
        'lib/a.dart': 'class A {}\n',
        'lib/z.dart': 'class Z {}\n',
        'test/a_test.dart':
            "import 'package:app/a.dart';\n"
            "import 'package:app/z.dart';\n"
            'void main() {}\n',
      },
      changes: ChangeSet([
        FileChange(path: RepoPath('lib/z.dart'), kind: ChangeKind.modified),
        FileChange(path: RepoPath('lib/a.dart'), kind: ChangeKind.modified),
      ]),
    );

    final result = await why.explain(RepoPath('test/a_test.dart'));

    expect(result.chains.map((chain) => chain.files.first.value), [
      'lib/a.dart',
      'lib/z.dart',
    ]);
  });

  test('a changed test file is its own chain', () {
    final result = _result('test/a_test.dart', [
      _chain(WhyOrigin.changed, ['test/a_test.dart']),
    ]);

    expect(renderWhy(result), '''
test/a_test.dart is affected by 1 changed file:

test/a_test.dart (changed)
''');
  });

  test(
    'a deleted file and the old path of a rename are labelled (deleted)',
    () {
      final result = _result('test/a_test.dart', [
        _chain(WhyOrigin.deleted, ['lib/old.dart', 'test/a_test.dart']),
        _chain(WhyOrigin.deleted, ['lib/gone.dart', 'test/a_test.dart']),
      ]);

      expect(renderWhy(result), contains('lib/old.dart (deleted)\n'));
      expect(renderWhy(result), contains('lib/gone.dart (deleted)\n'));
    },
  );

  test('a changed pubspec.yaml prints the configuration chain', () {
    final result = _result('test/a_test.dart', [
      _chain(WhyOrigin.configuration, ['pubspec.yaml'], package: _app),
    ]);

    expect(
      renderWhy(result),
      contains(
        'pubspec.yaml (changed)\n  configures every test of the package at .\n',
      ),
    );
  });

  test('an unaffected test says so', () {
    final none = _result('test/x_test.dart', const []);

    expect(
      renderWhy(none),
      'test/x_test.dart is not affected by the current changes.\n',
    );
  });

  test('explain builds the cart chain from the import graph', () async {
    final why = _why(
      index: _cartIndex,
      changes: ChangeSet([
        FileChange(
          path: RepoPath('lib/checkout/cart.dart'),
          kind: ChangeKind.modified,
        ),
      ]),
    );

    final result = await why.explain(RepoPath('test/checkout/cart_test.dart'));

    expect(renderWhy(result), '''
test/checkout/cart_test.dart is affected by 1 changed file:

lib/checkout/cart.dart (changed)
  imported by lib/checkout/cart_controller.dart
  imported by test/checkout/cart_test.dart
''');
  });

  test('a changed test file explain is its own chain', () async {
    final why = _why(
      index: {
        'pubspec.yaml': 'name: app\n',
        'test/a_test.dart': 'void main() {}\n',
      },
      changes: ChangeSet([
        FileChange(
          path: RepoPath('test/a_test.dart'),
          kind: ChangeKind.modified,
        ),
      ]),
    );

    final result = await why.explain(RepoPath('test/a_test.dart'));

    expect(renderWhy(result), contains('test/a_test.dart (changed)\n'));
    expect(result.chains.single.files, [RepoPath('test/a_test.dart')]);
  });

  test('deleted and rename old paths are labelled deleted', () async {
    final why = _why(
      index: {
        'pubspec.yaml': 'name: app\n',
        'lib/new.dart': 'class N {}\n',
        'test/a_test.dart':
            "import 'package:app/old.dart';\n"
            "import 'package:app/gone.dart';\n"
            'void main() {}\n',
      },
      changes: ChangeSet([
        FileChange(
          path: RepoPath('lib/new.dart'),
          kind: ChangeKind.renamed,
          previousPath: RepoPath('lib/old.dart'),
        ),
        FileChange(path: RepoPath('lib/gone.dart'), kind: ChangeKind.deleted),
      ]),
    );

    final result = await why.explain(RepoPath('test/a_test.dart'));

    expect(
      result.chains.map((chain) => (chain.files.first.value, chain.origin)),
      containsAll([
        ('lib/old.dart', WhyOrigin.deleted),
        ('lib/gone.dart', WhyOrigin.deleted),
      ]),
    );
  });

  test('changed pubspec.yaml prints the configuration chain', () async {
    final why = _why(
      index: {
        'pubspec.yaml': 'name: app\n',
        'test/a_test.dart': 'void main() {}\n',
      },
      changes: ChangeSet([
        FileChange(path: RepoPath('pubspec.yaml'), kind: ChangeKind.modified),
      ]),
    );

    final result = await why.explain(RepoPath('test/a_test.dart'));

    expect(
      renderWhy(result),
      contains(
        'pubspec.yaml (changed)\n  configures every test of the package at .\n',
      ),
    );
  });

  test(
    'a path that is not a test file of any package is a usage error',
    () async {
      final why = _why(
        index: {
          'pubspec.yaml': 'name: app\n',
          'lib/a.dart': '',
          'test/a_test.dart': 'void main() {}\n',
        },
        changes: ChangeSet(const []),
      );

      await expectLater(
        why.explain(RepoPath('lib/a.dart')),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            'lib/a.dart is not a test file of any package.',
          ),
        ),
      );
      await expectLater(
        why.explain(RepoPath('test/missing_test.dart')),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            'test/missing_test.dart is not a test file of any package.',
          ),
        ),
      );
    },
  );

  test('no test process and no analysis server is started', () async {
    final factory = FakeDartToolchainFactory();
    final why = _why(
      index: _cartIndex,
      changes: ChangeSet([
        FileChange(
          path: RepoPath('lib/checkout/cart.dart'),
          kind: ChangeKind.modified,
        ),
      ]),
      factory: factory,
    );

    await why.explain(RepoPath('test/checkout/cart_test.dart'));

    expect(factory.createCount, 1);
    final toolchain = factory.created.single;
    expect(toolchain.diagnoseCalls, isEmpty);
    expect(toolchain.closed, isTrue);
  });
}

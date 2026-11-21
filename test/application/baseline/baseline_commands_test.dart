import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/baseline/baseline.dart';
import 'package:stagelatch/src/application/baseline/baseline_codec.dart';
import 'package:stagelatch/src/application/baseline/baseline_commands.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/pipeline.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_check.dart';
import '../../support/fake_clock.dart';
import '../../support/fake_dart_toolchain_factory.dart';
import '../../support/fake_git_repository.dart';
import '../../support/fake_sdk_locator.dart';
import '../../support/fake_working_tree.dart';

const _path = '.stagelatch/baseline.json';

/// `pre-commit` selects nothing and `ci` selects `alpha`: the commands must
/// use the second.
const _config = 'hooks:\n  pre-commit: []\n  ci: [alpha]\n';

/// A check reporting a finding at each `(path, line)` of [at].
FakeCheck _alpha(List<(String, int)> at) {
  late final FakeCheck check;
  return check = FakeCheck(
    'alpha',
    onRun: (_) async => CheckResult(
      findings: [
        for (final (path, line) in at) check.finding(path, line: line),
      ],
    ),
  );
}

({BaselineCommands commands, FakeWorkingTree tree, FakeGitRepository git})
_setup(List<(String, int)> at, {Map<String, String> tree = const {}}) {
  final git = FakeGitRepository(
    index: {
      'stagelatch.yaml': _config,
      'a.txt': 'bad;\nbad;\nbad;\n',
      'b.txt': 'worse;\n',
    },
  );
  final workingTree = FakeWorkingTree(tree);
  final pipeline = Pipeline(
    git: git,
    configLoader: ConfigLoader(const StructuredDocuments(), workingTree),
    registry: CheckRegistry([_alpha(at)]),
    documents: const StructuredDocuments(),
    clock: FakeClock(),
    toolVersion: Version.parse('0.1.0'),
    sdkLocator: FakeSdkLocator(),
    toolchains: FakeDartToolchainFactory(),
  );
  return (
    commands: BaselineCommands(pipeline, workingTree),
    tree: workingTree,
    git: git,
  );
}

void main() {
  group('create', () {
    test('writes one entry per kind of finding, with its count', () async {
      final setup = _setup([('a.txt', 1), ('a.txt', 2), ('a.txt', 3)]);

      final message = await setup.commands.create(force: false);

      expect(message, 'Wrote 1 entry to $_path. Stage it to take effect.');
      final written = decodeBaseline(setup.tree.files[_path]!);
      expect(written.entries.single.count, 3);
      expect(written.entries.single.path.value, 'a.txt');
    });

    test('names several entries in the plural', () async {
      final setup = _setup([('a.txt', 1), ('b.txt', 1)]);

      expect(
        await setup.commands.create(force: false),
        'Wrote 2 entries to $_path. Stage it to take effect.',
      );
    });

    test('refuses to overwrite an existing file', () async {
      final setup = _setup([('a.txt', 1)], tree: {_path: 'precious'});

      await expectLater(
        setup.commands.create(force: false),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            '$_path already exists. Use --force to overwrite, '
                'or run: stagelatch baseline prune',
          ),
        ),
      );
      expect(setup.tree.files[_path], 'precious');
    });

    test('overwrites with --force', () async {
      final setup = _setup([('a.txt', 1)], tree: {_path: 'old'});

      await setup.commands.create(force: true);

      expect(decodeBaseline(setup.tree.files[_path]!).entries, hasLength(1));
    });

    test('with nothing to accept writes an empty baseline', () async {
      final setup = _setup(const []);

      expect(
        await setup.commands.create(force: false),
        'Wrote 0 entries to $_path. Stage it to take effect.',
      );
    });

    test('never stages anything', () async {
      final setup = _setup([('a.txt', 1)]);

      await setup.commands.create(force: false);

      expect(setup.git.appliedFixes, isEmpty);
    });
  });

  group('prune', () {
    Future<String> baselineText(List<(String, int)> at) async {
      final setup = _setup(at);
      await setup.commands.create(force: false);
      return setup.tree.files[_path]!;
    }

    test('lowers counts and removes stale entries', () async {
      final full = await baselineText([
        ('a.txt', 1),
        ('a.txt', 2),
        ('a.txt', 3),
        ('b.txt', 1),
      ]);
      final setup = _setup([('a.txt', 1), ('a.txt', 2)], tree: {_path: full});

      final message = await setup.commands.prune();

      expect(message, 'Removed 1 stale entry; 1 remain.');
      final written = decodeBaseline(setup.tree.files[_path]!);
      expect(written.entries.single.path.value, 'a.txt');
      expect(written.entries.single.count, 2);
    });

    test('never adds entries and never raises a count', () async {
      final small = await baselineText([('a.txt', 1)]);
      final setup = _setup(
        [('a.txt', 1), ('a.txt', 2), ('b.txt', 1)],
        tree: {_path: small},
      );

      final message = await setup.commands.prune();

      expect(message, 'Removed 0 stale entries; 1 remain.');
      final written = decodeBaseline(setup.tree.files[_path]!);
      expect(written.entries.single.count, 1);
    });

    test('without a baseline file says so and writes nothing', () async {
      final setup = _setup([('a.txt', 1)]);

      expect(await setup.commands.prune(), 'No baseline at $_path.');
      expect(setup.tree.files, isNot(contains(_path)));
    });

    test('a malformed file in the working tree is a config error', () async {
      final setup = _setup([('a.txt', 1)], tree: {_path: '{'});

      await expectLater(
        setup.commands.prune(),
        throwsA(isA<ConfigException>()),
      );
    });

    test('an entry of another rule is dropped', () async {
      final foreign = encodeBaseline(
        Baseline([
          BaselineEntry(
            rule: RuleId.parse('zeta/gone'),
            path: RepoPath('a.txt'),
            fingerprint: 'c' * 64,
            count: 2,
          ),
        ]),
      );
      final setup = _setup([('a.txt', 1)], tree: {_path: foreign});

      expect(await setup.commands.prune(), 'Removed 1 stale entry; 0 remain.');
    });
  });
}

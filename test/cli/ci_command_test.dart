@Tags(['git'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/application/hooks/hook_installer.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/pipeline.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/runner.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/fix.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/fake_check.dart';
import '../support/fake_clock.dart';
import '../support/fake_dart_toolchain_factory.dart';
import '../support/fake_git_repository.dart';
import '../support/fake_hook_store.dart';
import '../support/fake_sdk_locator.dart';
import '../support/fake_working_tree.dart';
import '../support/temp_repo.dart';

void main() {
  late TempRepo repo;

  Future<void> commitFile(String path, String content) async {
    await repo.write(path, content);
    await repo.stage(path);
    await repo.commit('change $path');
  }

  setUp(() async {
    repo = await TempRepo.create();
    await commitFile('stagelatch.yaml', 'hooks:\n  pre-commit: [pubspec]\n');
    await repo.git(['switch', '-q', '-c', 'feature']);
  });

  tearDown(() => repo.dispose());

  test('--base is required', () async {
    final result = await repo.stagelatch(['ci']);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('--base'));
  });

  test('a change on the branch is judged and blocks', () async {
    await commitFile('pubspec.yaml', badPubspec);

    final result = await repo.stagelatch(['ci', '--base', 'main']);

    expect(result.exitCode, 1);
    expect(result.stdout, startsWith('stagelatch ci: 1 file\n'));
    expect(result.stdout, contains('Failed.'));
  });

  test('changes on the base after the fork point are excluded', () async {
    await commitFile('notes.txt', 'n\n');
    await repo.git(['switch', '-q', 'main']);
    await commitFile('pubspec.yaml', badPubspec);
    await repo.git(['switch', '-q', 'feature']);

    final result = await repo.stagelatch(['ci', '--base', 'main']);

    expect(result.exitCode, 0, reason: result.stdout);
    expect(result.stdout, contains('Passed.'));
  });

  test(
    'without hooks.ci, ci runs the union of pre-commit and pre-push',
    () async {
      await commitFile(
        'stagelatch.yaml',
        'hooks:\n  pre-commit: []\n  pre-push: [pubspec]\n',
      );
      await commitFile('pubspec.yaml', badPubspec);

      final result = await repo.stagelatch(['ci', '--base', 'main']);

      expect(result.exitCode, 1);
      expect(result.stdout, contains('pubspec/path-dependency'));
    },
  );

  test('--reporter github prints workflow commands', () async {
    await commitFile('pubspec.yaml', badPubspec);

    final result = await repo.stagelatch([
      'ci',
      '--base',
      'main',
      '--reporter',
      'github',
    ]);

    expect(result.exitCode, 1);
    expect(
      result.stdout,
      startsWith(
        [
          '::error file=pubspec.yaml',
          'line=4',
          'col=11',
          'endLine=4',
          'endColumn=15',
          'title=pubspec/path-dependency::',
        ].join(','),
      ),
    );
  });

  test('--reporter json prints the JSON report with entry ci', () async {
    final result = await repo.stagelatch([
      'ci',
      '--base',
      'main',
      '--reporter',
      'json',
    ]);

    expect(result.exitCode, 0);
    expect((jsonDecode(result.stdout) as Map)['entry'], 'ci');
  });

  test(
    'an unknown reporter is a usage error naming the accepted values',
    () async {
      final result = await repo.stagelatch([
        'ci',
        '--base',
        'main',
        '--reporter',
        'sarif',
      ]);

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains('Unknown reporter "sarif". Expected console, json or github.'),
      );
    },
  );

  test('ci never applies fixes', () async {
    final git = FakeGitRepository(
      index: {'stagelatch.yaml': 'hooks:\n  ci: [fixer]\n', 'a.dart': 'x\n'},
    );
    late final FakeCheck fixer;
    fixer = FakeCheck(
      'fixer',
      phase: CheckPhase.fix,
      onRun: (_) async => CheckResult(
        findings: [fixer.finding('a.dart')],
        fixes: [
          Fix(
            rule: const RuleId('fixer', 'one'),
            path: RepoPath('a.dart'),
            content: 'fixed\n',
          ),
        ],
      ),
    );
    final registry = CheckRegistry([fixer]);
    final loader = ConfigLoader(const StructuredDocuments(), FakeWorkingTree());

    final code = await runStagelatch(
      ['ci', '--base', 'main'],
      Io(
        stdout: StringBuffer(),
        stderr: StringBuffer(),
        stdin: const Stream.empty(),
        environment: Environment(
          workingDirectory: Directory.current.path,
          variables: const {},
          stdoutIsTerminal: false,
          stdinIsTerminal: false,
        ),
      ),
      open: (_) async => Composition(
        pipeline: Pipeline(
          git: git,
          configLoader: loader,
          registry: registry,
          documents: const StructuredDocuments(),
          clock: FakeClock(),
          toolVersion: Version.parse('0.1.0'),
          sdkLocator: FakeSdkLocator(),
          toolchains: FakeDartToolchainFactory(),
        ),
        hookInstaller: HookInstaller(FakeHookStore()),
        git: git,
        documents: const StructuredDocuments(),
        registry: registry,
        loader: loader,
        worktree: FakeWorkingTree(),
        trackedHooks: () async => false,
      ),
    );

    expect(code, 1);
    expect(git.appliedFixes, isEmpty);
  });
}

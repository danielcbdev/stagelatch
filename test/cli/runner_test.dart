import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/application/hooks/hook_installer.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/pipeline.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/runner.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../support/fake_check.dart';
import '../support/fake_clock.dart';
import '../support/fake_git_repository.dart';
import '../support/fake_hook_store.dart';
import '../support/fake_working_tree.dart';
import '../support/temp_repo.dart';

void main() {
  test('--version prints the version and exits 0', () async {
    final out = StringBuffer();
    final code = await runStagelatch(
      ['--version'],
      Io(
        stdout: out,
        stderr: StringBuffer(),
        stdin: const Stream.empty(),
        environment: Environment(
          workingDirectory: Directory.current.path,
          variables: const {},
          stdoutIsTerminal: false,
          stdinIsTerminal: false,
        ),
      ),
    );

    expect(code, 0);
    expect(out.toString(), 'stagelatch 0.1.0-dev.1\n');
  });

  test('unknown command and unknown hook are usage errors', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);

    expect((await repo.stagelatch(['nope'])).exitCode, 64);
    expect((await repo.stagelatch(['run', 'post-merge'])).exitCode, 64);
  });

  test('outside a work tree is a usage error', () async {
    final empty = await Directory.systemTemp.createTemp('stagelatch_empty_');
    addTearDown(() => empty.delete(recursive: true));
    final err = StringBuffer();
    final code = await runStagelatch(
      ['run', 'pre-commit'],
      Io(
        stdout: StringBuffer(),
        stderr: err,
        stdin: const Stream.empty(),
        environment: Environment(
          workingDirectory: empty.path,
          variables: const {
            'GIT_CONFIG_NOSYSTEM': '1',
            'GIT_TERMINAL_PROMPT': '0',
          },
          stdoutIsTerminal: false,
          stdinIsTerminal: false,
        ),
      ),
    );

    expect(code, 64);
    expect(err.toString(), contains('Not inside a git work tree: '));
  });

  test('a blocking finding exits 1 and prints the report', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.write(
      'pubspec.yaml',
      'name: app\ndependencies:\n  design_system:\n    path: ../x\n',
    );
    await repo.stage('pubspec.yaml');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 1);
    expect(result.stdout, contains('pubspec/path-dependency'));
    expect(result.stdout, contains('Commit blocked'));
  });

  test('invalid config exits 78 with file, line and column', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.write('stagelatch.yaml', 'nope: true\n');
    await repo.stage('stagelatch.yaml');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 78);
    expect(result.stderr, contains('stagelatch.yaml:1:'));
  });

  test('init writes a config for this version and installs hooks', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);

    final result = await repo.stagelatch(['init']);

    expect(result.exitCode, 0);
    expect(
      await repo.read('stagelatch.yaml'),
      contains('pre-commit: [pubspec]'),
    );
    expect(result.stdout, contains('Created stagelatch.yaml.\n'));
    expect(result.stdout, contains('Installed pre-commit hook at '));
  });

  test('init refuses to overwrite without --force', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.write('stagelatch.yaml', 'hooks:\n  pre-commit: []\n');

    final result = await repo.stagelatch(['init']);

    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains('stagelatch.yaml already exists. Use --force to overwrite.'),
    );
  });

  test('init --no-hooks does not install', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);

    final result = await repo.stagelatch(['init', '--no-hooks']);
    final hooks = (await repo.git(['rev-parse', '--git-path', 'hooks'])).trim();
    final directory = p.isAbsolute(hooks) ? hooks : p.join(repo.root, hooks);

    expect(result.exitCode, 0);
    expect(File(p.join(directory, 'pre-commit')).existsSync(), isFalse);
  });

  test('install and uninstall print one line per hook', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.stagelatch(['init', '--no-hooks']);

    final installed = await repo.stagelatch(['install']);
    final removed = await repo.stagelatch(['uninstall']);

    expect(installed.exitCode, 0);
    expect(installed.stdout, contains('Installed pre-commit hook at '));
    expect(installed.stdout, contains('Installed pre-push hook at '));
    expect(removed.exitCode, 0);
    expect(removed.stdout, contains('Removed pre-commit hook.\n'));
    expect(removed.stdout, contains('Removed pre-push hook.\n'));
  });

  test('-C runs in another directory', () async {
    final here = await TempRepo.create();
    final there = await TempRepo.create();
    addTearDown(here.dispose);
    addTearDown(there.dispose);
    await there.write(
      'pubspec.yaml',
      'name: app\ndependencies:\n  design_system:\n    path: ../x\n',
    );
    await there.stage('pubspec.yaml');

    final result = await here.stagelatch([
      '-C',
      there.root,
      'run',
      'pre-commit',
    ]);

    expect(result.exitCode, 1);
    expect(result.stdout, contains('Commit blocked'));
  });

  test('an internal error names the check and exits 70', () async {
    final git = FakeGitRepository(
      index: {'stagelatch.yaml': 'hooks:\n  pre-commit: [boom]\n'},
    );
    final boom = FakeCheck(
      'boom',
      onRun: (_) async => throw StateError('nope'),
    );
    final err = StringBuffer();
    final code = await runStagelatch(
      ['run', 'pre-commit'],
      Io(
        stdout: StringBuffer(),
        stderr: err,
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
          configLoader: ConfigLoader(
            const StructuredDocuments(),
            FakeWorkingTree(),
          ),
          registry: CheckRegistry([boom]),
          documents: const StructuredDocuments(),
          clock: FakeClock(),
          toolVersion: Version.parse('0.1.0-dev.1'),
        ),
        hookInstaller: HookInstaller(FakeHookStore()),
        git: git,
        documents: const StructuredDocuments(),
        registry: CheckRegistry([boom]),
        loader: ConfigLoader(const StructuredDocuments(), FakeWorkingTree()),
        worktree: FakeWorkingTree(),
        trackedHooks: () async => false,
      ),
    );

    expect(code, 70);
    expect(
      err.toString(),
      startsWith('stagelatch: internal error in check "boom": '),
    );
    expect(
      err.toString(),
      contains('To proceed anyway: git commit --no-verify\n'),
    );
  });
}

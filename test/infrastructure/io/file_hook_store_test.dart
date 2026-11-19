import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/hooks/hook_name.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:stagelatch/src/infrastructure/io/file_hook_store.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('stagelatch_hooks_');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('writes bytes verbatim and sets the executable bit', () async {
    final store = FileHookStore(hooksDirectory: p.join(temp.path, 'hooks'));
    const script = '#!/bin/sh\n# stagelatch:managed\necho hi\n';

    await store.write(HookName.preCommit, script);

    final file = File(store.pathOf(HookName.preCommit));
    expect(await file.readAsBytes(), utf8.encode(script));
    expect(await store.read(HookName.preCommit), script);
    if (!Platform.isWindows) {
      // Unix permission bits. Windows has no mode to assert.
      expect(file.statSync().mode & 0x1FF, 0x1ED);
    }
  });

  test('a .sample file is not the hook', () async {
    final hooks = Directory(p.join(temp.path, 'hooks'))..createSync();
    final sample = File(p.join(hooks.path, 'pre-commit.sample'));
    await sample.writeAsString('sample\n');
    final store = FileHookStore(hooksDirectory: hooks.path);

    expect(await store.read(HookName.preCommit), isNull);
  });

  test('a second backup is numbered and restore uses the newest', () async {
    final store = FileHookStore(hooksDirectory: p.join(temp.path, 'hooks'));
    await store.write(HookName.preCommit, 'first\n');
    final first = p.basename(await store.backup(HookName.preCommit));
    await store.write(HookName.preCommit, 'second\n');
    final second = p.basename(await store.backup(HookName.preCommit));

    expect(first, 'pre-commit.stagelatch-backup');
    expect(second, 'pre-commit.stagelatch-backup.1');

    await store.delete(HookName.preCommit);
    final restored = await store.restoreLatestBackup(HookName.preCommit);
    expect(p.basename(restored ?? ''), second);
    expect(await store.read(HookName.preCommit), 'second\n');
  });

  test(
    'refuses a hook path that resolves outside the hooks directory',
    () async {
      final hooks = Directory(p.join(temp.path, 'hooks'))..createSync();
      final outside = File(p.join(temp.path, 'outside'))
        ..writeAsStringSync('safe\n');
      Link(p.join(hooks.path, 'pre-commit')).createSync(outside.path);
      final store = FileHookStore(hooksDirectory: hooks.path);

      expect(
        store.write(HookName.preCommit, '#!/bin/sh\n# stagelatch:managed\n'),
        throwsA(isA<UsageException>()),
      );
      expect(outside.readAsStringSync(), 'safe\n');
    },
    skip: Platform.isWindows
        ? 'Creating a symlink needs a privilege the Windows '
              'runner may not have.'
        : null,
  );

  test('a committed hooks directory inside the work tree is tracked', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.write('.githooks/pre-commit', '#!/bin/sh\n');
    await repo.git(['add', '.githooks/pre-commit']);
    await repo.commit('track hooks');
    final store = FileHookStore(
      hooksDirectory: p.join(repo.root, '.githooks'),
      git: GitProcess(
        workingDirectory: repo.root,
        environment: repo.environment,
      ),
    );

    expect(await store.directoryIsTracked, isTrue);
  });

  test('the default git hooks directory is not tracked', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    final reported = (await repo.git(['rev-parse', '--git-path', 'hooks']))
        .trim();
    final hooks = p.isAbsolute(reported)
        ? reported
        : p.join(repo.root, reported);
    final store = FileHookStore(
      hooksDirectory: hooks,
      git: GitProcess(
        workingDirectory: repo.root,
        environment: repo.environment,
      ),
    );

    expect(await store.directoryIsTracked, isFalse);
  });
}

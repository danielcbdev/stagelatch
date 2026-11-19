@Tags(['git'])
library;

import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:stagelatch/src/infrastructure/git/cat_file_batch.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:stagelatch/src/infrastructure/git/git_snapshot_files.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

void main() {
  late TempRepo repo;
  late GitProcess git;
  late CatFileBatch batch;

  /// A fresh view: the listing is read once per instance.
  GitSnapshotFiles snapshot([SnapshotRef ref = const IndexSnapshot()]) =>
      GitSnapshotFiles(git: git, batch: batch, ref: ref);

  Future<String> head() async => (await repo.git(['rev-parse', 'HEAD'])).trim();

  setUp(() async {
    repo = await TempRepo.create();
    git = GitProcess(
      workingDirectory: repo.root,
      environment: repo.environment,
    );
    batch = CatFileBatch(git);
  });

  tearDown(() async {
    await batch.close();
    await repo.dispose();
  });

  group('index snapshot', () {
    test('returns staged content, not working tree content', () async {
      await repo.write('a.txt', 'disk');
      await repo.stageContent('a.txt', 'staged');

      expect(await snapshot().readText(RepoPath('a.txt')), 'staged');
    });

    test('lists entries sorted by path with their modes', () async {
      await repo.write('run.sh', '#!/bin/sh\n');
      await repo.stage('run.sh');
      await repo.git(['update-index', '--chmod=+x', 'run.sh']);
      final target = await repo.git([
        'hash-object',
        '-w',
        '--stdin',
      ], stdin: 'README.md');
      await repo.git([
        'update-index',
        '--add',
        '--cacheinfo',
        '120000,${target.trim()},link',
      ]);
      await repo.git([
        'update-index',
        '--add',
        '--cacheinfo',
        '160000,${await head()},vendor/lib',
      ]);

      final entries = await snapshot().list();

      expect(
        {for (final entry in entries) entry.path.value: entry.mode},
        {
          'README.md': FileMode.regular,
          'link': FileMode.symlink,
          'run.sh': FileMode.executable,
          'vendor/lib': FileMode.gitlink,
        },
      );
      expect(entries.map((entry) => entry.path.value), [
        'README.md',
        'link',
        'run.sh',
        'vendor/lib',
      ]);
    });

    test('limits a listing to a directory', () async {
      await repo.stageContent('lib/a.dart', '');
      await repo.stageContent('lib/src/b.dart', '');
      await repo.stageContent('library/c.dart', '');

      final entries = await snapshot().list(under: RepoPath('lib'));

      expect(entries.map((entry) => entry.path.value), [
        'lib/a.dart',
        'lib/src/b.dart',
      ]);
    });

    test('finds an entry by path, with the blob id git gave it', () async {
      final files = snapshot();
      final blob = (await repo.git(['rev-parse', ':README.md'])).trim();

      expect((await files.entry(RepoPath('README.md')))?.blobId, blob);
      expect(await files.entry(RepoPath('missing.txt')), isNull);
    });

    test('readText is null for a missing path', () async {
      expect(await snapshot().readText(RepoPath('missing.txt')), isNull);
      expect(await snapshot().readBytes(RepoPath('missing.txt')), isNull);
      expect(await snapshot().size(RepoPath('missing.txt')), isNull);
    });

    test('readText is null for binary content', () async {
      await repo.writeBytes('a.bin', [0x41, 0x00, 0x42]);
      await repo.stage('a.bin');

      expect(await snapshot().readText(RepoPath('a.bin')), isNull);
      expect(await snapshot().readBytes(RepoPath('a.bin')), [0x41, 0, 0x42]);
      expect(await snapshot().size(RepoPath('a.bin')), 3);
    });

    test('readText is null for bytes that are not valid UTF-8', () async {
      await repo.writeBytes('latin1.txt', [0xC3, 0x28]);
      await repo.stage('latin1.txt');

      expect(await snapshot().readText(RepoPath('latin1.txt')), isNull);
    });

    test('readText is null for a symlink and for a gitlink', () async {
      final target = await repo.git([
        'hash-object',
        '-w',
        '--stdin',
      ], stdin: 'README.md');
      await repo.git([
        'update-index',
        '--add',
        '--cacheinfo',
        '120000,${target.trim()},link',
      ]);
      await repo.git([
        'update-index',
        '--add',
        '--cacheinfo',
        '160000,${await head()},vendor/lib',
      ]);
      final files = snapshot();

      expect(await files.readText(RepoPath('link')), isNull);
      expect(await files.readText(RepoPath('vendor/lib')), isNull);
      expect(await files.readBytes(RepoPath('vendor/lib')), isNull);
      expect(await files.size(RepoPath('vendor/lib')), isNull);
    });

    test('readText is null for a file above the size limit', () async {
      await repo.writeBytes('big.txt', List.filled(maxTextBytes + 1, 0x61));
      await repo.stage('big.txt');

      expect(await snapshot().readText(RepoPath('big.txt')), isNull);
      expect(await snapshot().size(RepoPath('big.txt')), maxTextBytes + 1);
    });

    test('strips a byte order mark and preserves CRLF', () async {
      await repo.writeBytes('crlf.txt', [
        0xEF,
        0xBB,
        0xBF,
        ...'a\r\nb\r\n'.codeUnits,
      ]);
      await repo.stage('crlf.txt');

      expect(await snapshot().readText(RepoPath('crlf.txt')), 'a\r\nb\r\n');
    });

    test('handles paths with spaces and non-ASCII characters', () async {
      await repo.stageContent('dir with space/ação.txt', 'ok');

      final files = snapshot();

      expect(await files.readText(RepoPath('dir with space/ação.txt')), 'ok');
      expect(
        (await files.list()).map((entry) => entry.path.value),
        contains('dir with space/ação.txt'),
      );
    });

    test('handles paths with a quote and with a newline', () async {
      await repo.stageContent('q"uote.txt', 'quote');
      await repo.stageContent('new\nline.txt', 'newline');

      final files = snapshot();

      expect(await files.readText(RepoPath('q"uote.txt')), 'quote');
      expect(await files.readText(RepoPath('new\nline.txt')), 'newline');
    }, testOn: '!windows');

    test('unmerged index entries are a usage error', () async {
      await repo.write('c.txt', 'base\n');
      await repo.stage('c.txt');
      await repo.commit('base');
      await repo.git(['switch', '--quiet', '-c', 'feature']);
      await repo.write('c.txt', 'feature\n');
      await repo.stage('c.txt');
      await repo.commit('feature');
      await repo.git(['switch', '--quiet', 'main']);
      await repo.write('c.txt', 'main\n');
      await repo.stage('c.txt');
      await repo.commit('main');
      await repo.git(['merge', 'feature'], okExitCodes: {1});

      expect(
        () => snapshot().list(),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            'The index has unmerged paths; resolve conflicts first.',
          ),
        ),
      );
    });
  });

  group('commit snapshot', () {
    test('returns committed content, not staged content', () async {
      await repo.stageContent('README.md', 'staged, not committed\n');

      final files = snapshot(CommitSnapshot(await head()));

      expect(await files.readText(RepoPath('README.md')), 'test repository\n');
    });

    test('lists the tree recursively, sorted, with modes', () async {
      await repo.write('lib/src/a.dart', '');
      await repo.stage('lib/src/a.dart');
      await repo.write('run.sh', '');
      await repo.stage('run.sh');
      await repo.git(['update-index', '--chmod=+x', 'run.sh']);
      await repo.commit('more');

      final entries = await snapshot(CommitSnapshot(await head())).list();

      expect(
        {for (final entry in entries) entry.path.value: entry.mode},
        {
          'README.md': FileMode.regular,
          'lib/src/a.dart': FileMode.regular,
          'run.sh': FileMode.executable,
        },
      );
    });
  });
}

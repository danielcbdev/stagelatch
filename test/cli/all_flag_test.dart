@Tags(['git'])
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  late TempRepo repo;

  /// A repository whose committed pubspec has a violation, and nothing
  /// staged: only `--all` can see the violation.
  setUp(() async {
    repo = await TempRepo.create();
    await repo.stageContent(
      'stagelatch.yaml',
      'hooks:\n  pre-commit: [pubspec]\n  pre-push: [pubspec]\n',
    );
    await repo.stageContent('pubspec.yaml', badPubspec);
    await repo.commit('legacy violation');
  });

  tearDown(() => repo.dispose());

  test(
    'run pre-commit --all reports a violation in an unchanged file',
    () async {
      final plain = await repo.stagelatch(['run', 'pre-commit']);
      final all = await repo.stagelatch(['run', 'pre-commit', '--all']);

      expect(plain.exitCode, 0);
      expect(plain.stdout, startsWith('stagelatch pre-commit: 0 files\n'));
      expect(all.exitCode, 1, reason: all.stdout + all.stderr);
      expect(all.stdout, contains('pubspec/path-dependency'));
      expect(all.stdout, contains('Commit blocked'));
    },
  );

  test('the console header says it ran on all files, with the count', () async {
    final result = await repo.stagelatch(['run', 'pre-commit', '--all']);

    expect(
      result.stdout,
      startsWith('stagelatch pre-commit: all 3 files\n'),
      reason: 'stagelatch.yaml, pubspec.yaml and the initial commit file',
    );
  });

  test('the JSON report has "all" right after "files"', () async {
    final all = await repo.stagelatch([
      'run',
      'pre-commit',
      '--all',
      '--reporter',
      'json',
    ]);
    await repo.stageContent('README.md', '# x\n');
    final plain = await repo.stagelatch([
      'run',
      'pre-commit',
      '--reporter',
      'json',
    ]);

    final allJson = jsonDecode(all.stdout) as Map<String, Object?>;
    final plainJson = jsonDecode(plain.stdout) as Map<String, Object?>;
    expect(allJson['all'], isTrue);
    expect(plainJson['all'], isFalse);
    final keys = allJson.keys.toList();
    expect(keys.indexOf('all'), keys.indexOf('files') + 1);
  });

  test('ci --all judges every file of the head commit', () async {
    await repo.git(['switch', '-q', '-c', 'feature']);
    await repo.stageContent('notes.txt', 'n\n');
    await repo.commit('notes');

    final plain = await repo.stagelatch(['ci', '--base', 'main']);
    final all = await repo.stagelatch(['ci', '--base', 'main', '--all']);

    expect(plain.exitCode, 0, reason: plain.stdout + plain.stderr);
    expect(all.exitCode, 1, reason: all.stdout + all.stderr);
    expect(all.stdout, startsWith('stagelatch ci: all 4 files\n'));
  });

  test('run pre-push --all judges every file of the pushed commit', () async {
    final remote = await TempRepo.create(initialCommit: false);
    addTearDown(remote.dispose);
    await repo.git(['remote', 'add', 'origin', remote.root]);
    final head = (await repo.git(['rev-parse', 'HEAD'])).trim();

    final result = await repo.stagelatch([
      'run',
      'pre-push',
      'origin',
      remote.root,
      '--all',
    ], stdin: 'refs/heads/main $head refs/heads/main ${'0' * 40}\n');

    expect(result.exitCode, 1, reason: result.stdout + result.stderr);
    expect(result.stdout, contains('stagelatch pre-push main: all 3 files'));
    expect(result.stdout, contains('Push blocked'));
  });
}

@Tags(['git'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/infrastructure/git/git_cli_repository.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

void main() {
  late TempRepo repo;
  late GitCliRepository git;

  Future<String> sha(String rev) async =>
      (await repo.git(['rev-parse', rev])).trim();

  Future<void> commitFile(String path, String content) async {
    await repo.write(path, content);
    await repo.stage(path);
    await repo.commit('change $path');
  }

  GitCliRepository open(String directory) => GitCliRepository(
    git: GitProcess(workingDirectory: directory, environment: repo.environment),
  );

  setUp(() async {
    repo = await TempRepo.create();
    git = open(repo.root);
  });

  tearDown(() async {
    await git.close();
    await repo.dispose();
  });

  test('the changeset is merge-base(base, head)..head', () async {
    await commitFile('base.txt', 'b\n');
    await repo.git(['switch', '-q', '-c', 'feature']);
    await commitFile('feature.txt', 'f\n');
    await repo.git(['switch', '-q', 'main']);
    await commitFile('main_only.txt', 'm\n');
    await repo.git(['switch', '-q', 'feature']);
    final forkPoint = await sha('feature~1');

    final run = (await git.resolve(
      const CiEntry(baseRef: 'main'),
      all: false,
    )).single;

    expect(
      [for (final change in run.changes.changes) change.path.value],
      ['feature.txt'],
    );
    expect(run.snapshot, CommitSnapshot(await sha('HEAD')));
    expect(run.base, CommitSnapshot(forkPoint));
    expect(run.targetBranch, 'main');
  });

  test('--head names the commit to judge', () async {
    await commitFile('a.txt', 'a\n');
    await repo.git(['branch', 'topic']);
    await commitFile('b.txt', 'b\n');

    final run = (await git.resolve(
      const CiEntry(baseRef: 'HEAD~2', headRef: 'topic'),
      all: false,
    )).single;

    expect(
      [for (final change in run.changes.changes) change.path.value],
      ['a.txt'],
    );
    expect(run.snapshot, CommitSnapshot(await sha('topic')));
  });

  test('the target branch drops a leading origin/ or refs/heads/', () async {
    await commitFile('a.txt', 'a\n');
    await repo.git(['update-ref', 'refs/remotes/origin/develop', 'HEAD']);

    final viaRemote = (await git.resolve(
      const CiEntry(baseRef: 'origin/develop'),
      all: false,
    )).single;
    final viaHeads = (await git.resolve(
      const CiEntry(baseRef: 'refs/heads/main'),
      all: false,
    )).single;

    expect(viaRemote.targetBranch, 'develop');
    expect(viaHeads.targetBranch, 'main');
  });

  test('a shallow clone without a merge base is a usage error asking for '
      'full history', () async {
    await commitFile('a.txt', 'a\n');
    await repo.git(['switch', '-q', '-c', 'feature']);
    await commitFile('f.txt', 'f\n');
    final clones = await Directory.systemTemp.createTemp('stagelatch_clone_');
    addTearDown(() => clones.delete(recursive: true));
    final clone = p.join(clones.path, 'clone');
    await repo.git([
      'clone',
      '-q',
      '--depth',
      '1',
      '--branch',
      'feature',
      Uri.directory(repo.root).toString(),
      clone,
    ]);
    final shallow = open(clone);
    addTearDown(shallow.close);

    await expectLater(
      shallow.resolve(const CiEntry(baseRef: 'origin/main'), all: false),
      throwsA(
        isA<UsageException>().having(
          (e) => e.message,
          'message',
          'Cannot find a merge base between origin/main and HEAD. If this is '
              'a shallow clone, fetch full history (actions/checkout: '
              'fetch-depth: 0).',
        ),
      ),
    );
  });
}

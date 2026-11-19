@Tags(['git'])
library;

import 'dart:io';

import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/git/git_cli_repository.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

const _zeros = '0000000000000000000000000000000000000000';

void main() {
  late TempRepo repo;
  late GitCliRepository git;
  late Directory remoteDir;

  Future<String> sha(String rev) async =>
      (await repo.git(['rev-parse', rev])).trim();

  Future<void> commitFile(String path, String content) async {
    await repo.write(path, content);
    await repo.stage(path);
    await repo.commit('change $path');
  }

  Future<List<ResolvedRun>> push(List<PushedRef> refs) =>
      git.resolve(PrePushEntry(remote: 'origin', refs: refs), all: false);

  PushedRef ref(String branch, String localSha, String remoteSha) => PushedRef(
    localRef: 'refs/heads/$branch',
    localSha: localSha,
    remoteRef: 'refs/heads/$branch',
    remoteSha: remoteSha,
  );

  List<String> changed(ResolvedRun run) => [
    for (final change in run.changes.changes) change.path.value,
  ];

  setUp(() async {
    repo = await TempRepo.create();
    git = GitCliRepository(
      git: GitProcess(
        workingDirectory: repo.root,
        environment: repo.environment,
      ),
    );
    remoteDir = await Directory.systemTemp.createTemp('stagelatch_remote_');
    await repo.git(['init', '-q', '--bare', remoteDir.path]);
    await repo.git(['remote', 'add', 'origin', remoteDir.path]);
  });

  tearDown(() async {
    await git.close();
    await repo.dispose();
    await remoteDir.delete(recursive: true);
  });

  test('existing branch: base is the remote sha', () async {
    await commitFile('base.txt', 'base\n');
    await repo.git(['push', '-q', 'origin', 'main']);
    final remoteSha = await sha('HEAD');
    await commitFile('a.txt', 'a\n');

    final run = (await push([ref('main', await sha('HEAD'), remoteSha)]))
        .single;

    expect(changed(run), ['a.txt']);
    expect(run.base, CommitSnapshot(remoteSha));
    expect(run.snapshot, CommitSnapshot(await sha('HEAD')));
    expect(run.targetBranch, 'main');
    expect(run.label, 'main');
  });

  test(
    "new branch: base is the merge-base with the remote's branches",
    () async {
      await commitFile('base.txt', 'base\n');
      await repo.git(['push', '-q', 'origin', 'main']);
      await repo.git(['switch', '-q', '-c', 'develop']);
      await commitFile('develop.txt', 'd\n');
      await repo.git(['push', '-q', 'origin', 'develop']);
      await repo.git(['switch', '-q', '-c', 'feature']);
      await commitFile('only_in_feature.txt', 'f\n');
      await commitFile('only_in_feature.txt', 'f2\n');

      final run = (await push([ref('feature', await sha('HEAD'), _zeros)]))
          .single;

      expect(changed(run), ['only_in_feature.txt']);
      expect(run.targetBranch, 'feature');
    },
  );

  test('first push of a repository: base is the empty tree', () async {
    await commitFile('a.txt', 'a\n');
    await commitFile('b/c.txt', 'c\n');

    final run = (await push([ref('main', await sha('HEAD'), _zeros)])).single;

    expect(run.base, isNull);
    expect(changed(run), ['README.md', 'a.txt', 'b/c.txt']);
    expect(run.changes.changes.map((change) => change.kind).toSet(), {
      ChangeKind.added,
    });
  });

  test('branch deletion and tag pushes produce no run', () async {
    await commitFile('a.txt', 'a\n');
    final head = await sha('HEAD');

    final runs = await push([
      PushedRef(
        localRef: '(delete)',
        localSha: _zeros,
        remoteRef: 'refs/heads/old',
        remoteSha: head,
      ),
      PushedRef(
        localRef: 'refs/tags/v1',
        localSha: head,
        remoteRef: 'refs/tags/v1',
        remoteSha: _zeros,
      ),
    ]);

    expect(runs, isEmpty);
  });

  test(
    'a remote sha that is unknown locally falls back to the merge-base rule',
    () async {
      await commitFile('base.txt', 'base\n');
      await repo.git(['push', '-q', 'origin', 'main']);
      await commitFile('a.txt', 'a\n');

      final run = (await push([
        ref(
          'main',
          await sha('HEAD'),
          '1234567890123456789012345678901234567890',
        ),
      ])).single;

      expect(changed(run), ['a.txt']);
    },
  );

  test('the snapshot is the pushed commit, not the index', () async {
    await commitFile('a.txt', 'committed\n');
    await repo.write('a.txt', 'staged\n');
    await repo.stage('a.txt');

    final run = (await push([ref('main', await sha('HEAD'), _zeros)])).single;

    expect(
      await git.files(run.snapshot).readText(RepoPath('a.txt')),
      'committed\n',
    );
  });

  test('two pushed branches produce two runs, in ref order', () async {
    await commitFile('a.txt', 'a\n');
    await repo.git(['branch', 'other']);
    final head = await sha('HEAD');

    final runs = await push([
      ref('other', head, _zeros),
      ref('main', head, _zeros),
    ]);

    expect(runs.map((run) => run.label), ['other', 'main']);
  });

  group('synthesizePrePush', () {
    test('without stdin, one ref is synthesized from the current branch and '
        'its upstream', () async {
      await commitFile('a.txt', 'a\n');
      await repo.git(['push', '-q', '-u', 'origin', 'main']);
      final pushed = await sha('HEAD');
      await commitFile('b.txt', 'b\n');

      final entry = await git.synthesizePrePush();

      expect(entry.remote, 'origin');
      final only = entry.refs.single;
      expect(only.localRef, 'refs/heads/main');
      expect(only.localSha, await sha('HEAD'));
      expect(only.remoteRef, 'refs/heads/main');
      expect(only.remoteSha, pushed);
    });

    test('without stdin, no upstream and no remote argument, the remote is '
        'origin', () async {
      await commitFile('a.txt', 'a\n');

      final entry = await git.synthesizePrePush();

      expect(entry.remote, 'origin');
      expect(entry.refs.single.remoteRef, 'refs/heads/main');
      expect(entry.refs.single.remoteSha, _zeros);
    });

    test('a remote argument wins', () async {
      await commitFile('a.txt', 'a\n');

      final entry = await git.synthesizePrePush(remote: 'upstream');

      expect(entry.remote, 'upstream');
    });

    test('a detached HEAD pushes nothing', () async {
      await commitFile('a.txt', 'a\n');
      await repo.git(['switch', '-q', '--detach']);

      expect((await git.synthesizePrePush()).refs, isEmpty);
    });
  });
}

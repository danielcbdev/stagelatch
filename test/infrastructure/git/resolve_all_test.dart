@Tags(['git'])
library;

import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/infrastructure/git/git_cli_repository.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

void main() {
  late TempRepo repo;
  late GitCliRepository git;

  Future<void> commitFile(String path, String content) async {
    await repo.write(path, content);
    await repo.stage(path);
    await repo.commit('change $path');
  }

  /// Puts a symlink and a submodule entry in the index, without needing
  /// the platform to create either.
  Future<void> stageSymlinkAndSubmodule() async {
    final target = (await repo.git([
      'hash-object',
      '-w',
      '--stdin',
    ], stdin: 'a.txt')).trim();
    await repo.git([
      'update-index',
      '--add',
      '--cacheinfo',
      '120000,$target,link',
    ]);
    final head = (await repo.git(['rev-parse', 'HEAD'])).trim();
    await repo.git([
      'update-index',
      '--add',
      '--cacheinfo',
      '160000,$head,vendor/sub',
    ]);
  }

  List<String> paths(ChangeSet changes) => [
    for (final change in changes.changes) change.path.value,
  ];

  setUp(() async {
    repo = await TempRepo.create();
    git = GitCliRepository(
      git: GitProcess(
        workingDirectory: repo.root,
        environment: repo.environment,
      ),
    );
  });

  tearDown(() async {
    await git.close();
    await repo.dispose();
  });

  test('all lists every regular file of the snapshot as added; symlinks and '
      'gitlinks are left out', () async {
    await commitFile('a.txt', 'a\n');
    await commitFile('lib/b.dart', 'b\n');
    await stageSymlinkAndSubmodule();

    final run = (await git.resolve(const PreCommitEntry(), all: true)).single;

    expect(paths(run.changes), ['README.md', 'a.txt', 'lib/b.dart']);
    expect(
      run.changes.changes.every((change) => change.kind == ChangeKind.added),
      isTrue,
    );
  });

  test('the files are those of the index, not of the working tree', () async {
    await commitFile('a.txt', 'a\n');
    await repo.write('untracked.txt', 'u\n');
    await repo.stageContent('staged_only.txt', 's\n');
    await repo.delete('a.txt');

    final run = (await git.resolve(const PreCommitEntry(), all: true)).single;

    expect(paths(run.changes), ['README.md', 'a.txt', 'staged_only.txt']);
  });

  test('the base is still resolved, as without --all', () async {
    await commitFile('a.txt', 'a\n');

    final all = (await git.resolve(const PreCommitEntry(), all: true)).single;
    final plain = (await git.resolve(
      const PreCommitEntry(),
      all: false,
    )).single;

    expect(all.base, isNotNull);
    expect(all.base, plain.base);
    expect(all.targetBranch, 'main');
    expect(all.label, 'index');
  });

  test('on a repository with no commit the index is listed and there is no '
      'base', () async {
    final fresh = await TempRepo.create(initialCommit: false);
    addTearDown(fresh.dispose);
    await fresh.stageContent('a.txt', 'a\n');
    final other = GitCliRepository(
      git: GitProcess(
        workingDirectory: fresh.root,
        environment: fresh.environment,
      ),
    );
    addTearDown(other.close);

    final run = (await other.resolve(const PreCommitEntry(), all: true)).single;

    expect(paths(run.changes), ['a.txt']);
    expect(run.base, isNull);
  });

  test('ci lists every file of the head commit, the base as usual', () async {
    await commitFile('a.txt', 'a\n');
    await repo.git(['switch', '-q', '-c', 'feature']);
    await commitFile('b.txt', 'b\n');

    final run = (await git.resolve(
      const CiEntry(baseRef: 'main'),
      all: true,
    )).single;

    expect(paths(run.changes), ['README.md', 'a.txt', 'b.txt']);
    expect(run.base, isNotNull);
  });

  test('pre-push lists every file of each pushed commit', () async {
    await commitFile('a.txt', 'a\n');
    final remote = await TempRepo.create(initialCommit: false);
    addTearDown(remote.dispose);
    await repo.git(['remote', 'add', 'origin', remote.root]);
    await commitFile('b.txt', 'b\n');
    final head = (await repo.git(['rev-parse', 'HEAD'])).trim();

    final runs = await git.resolve(
      PrePushEntry(
        remote: 'origin',
        refs: [
          PushedRef(
            localRef: 'refs/heads/main',
            localSha: head,
            remoteRef: 'refs/heads/main',
            remoteSha: '0' * 40,
          ),
        ],
      ),
      all: true,
    );

    expect(paths(runs.single.changes), ['README.md', 'a.txt', 'b.txt']);
  });
}

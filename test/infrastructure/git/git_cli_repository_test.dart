@Tags(['git'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/git/git_cli_repository.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

/// Matches a path that names the same location as [expected], whatever the
/// separator or letter case the platform reports.
Matcher _samePath(String expected) => predicate<String>(
  (actual) => p.equals(actual, expected),
  'is the path $expected',
);

void main() {
  late TempRepo repo;
  late GitCliRepository git;

  GitCliRepository open(String directory) => GitCliRepository(
    git: GitProcess(workingDirectory: directory, environment: repo.environment),
  );

  Future<ResolvedRun> preCommit() async =>
      (await git.resolve(const PreCommitEntry(), all: false)).single;

  Future<void> commitFile(String path, String content, String message) async {
    await repo.write(path, content);
    await repo.stage(path);
    await repo.commit(message);
  }

  setUp(() async {
    repo = await TempRepo.create();
    git = open(repo.root);
  });

  tearDown(() async {
    await git.close();
    await repo.dispose();
  });

  group('layout', () {
    test('describes an ordinary repository', () async {
      final layout = await git.layout();

      expect(layout.root, _samePath(repo.root));
      expect(layout.gitDir, _samePath(p.join(repo.root, '.git')));
      expect(layout.commonDir, _samePath(p.join(repo.root, '.git')));
      expect(layout.hooksDir, _samePath(p.join(repo.root, '.git', 'hooks')));
      expect(layout.branch, 'main');
      expect(layout.mergeInProgress, isFalse);
      expect(layout.rebaseInProgress, isFalse);
      expect(layout.shallow, isFalse);
    });

    test('works from a subdirectory', () async {
      await Directory(p.join(repo.root, 'lib', 'src')).create(recursive: true);
      final nested = open(p.join(repo.root, 'lib', 'src'));
      addTearDown(nested.close);

      final layout = await nested.layout();

      expect(layout.root, _samePath(repo.root));
      expect(layout.hooksDir, _samePath(p.join(repo.root, '.git', 'hooks')));
    });

    test('reports the hooks directory under core.hooksPath', () async {
      await repo.git(['config', 'core.hooksPath', '.husky']);

      final layout = await open(repo.root).layout();

      expect(layout.hooksDir, _samePath(p.join(repo.root, '.husky')));
    });

    test('resolves a relative core.hooksPath against the root', () async {
      await repo.git(['config', 'core.hooksPath', '.husky']);
      await Directory(p.join(repo.root, 'lib')).create();
      final nested = open(p.join(repo.root, 'lib'));
      addTearDown(nested.close);

      final layout = await nested.layout();

      expect(layout.hooksDir, _samePath(p.join(repo.root, '.husky')));
    });

    test('in a linked worktree, hooks live in the common directory', () async {
      final worktree = p.join(p.dirname(repo.root), 'linked');
      await repo.git(['worktree', 'add', '--quiet', '-b', 'side', worktree]);
      final linked = open(worktree);
      addTearDown(linked.close);

      final layout = await linked.layout();

      expect(layout.root, _samePath(worktree));
      expect(layout.commonDir, _samePath(p.join(repo.root, '.git')));
      expect(
        layout.gitDir,
        _samePath(p.join(repo.root, '.git', 'worktrees', 'linked')),
      );
      expect(layout.hooksDir, _samePath(p.join(repo.root, '.git', 'hooks')));
      expect(layout.branch, 'side');
    });

    test('has no branch on a detached HEAD', () async {
      await repo.git(['switch', '--quiet', '--detach']);

      expect((await open(repo.root).layout()).branch, isNull);
    });

    test('outside a work tree is a usage error', () async {
      final plain = await Directory.systemTemp.createTemp('stagelatch_plain_');
      addTearDown(() => plain.delete(recursive: true));
      final outside = open(plain.path);

      expect(
        outside.layout,
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            'Not inside a git work tree: ${plain.path}.',
          ),
        ),
      );
    });
  });

  group('pre-commit changeset', () {
    test('lists added, modified, deleted and renamed paths', () async {
      await commitFile('old.txt', 'a long enough line to be a rename\n', 'x');
      await commitFile('gone.txt', 'bye\n', 'y');
      await repo.write('README.md', 'changed\n');
      await repo.stage('README.md');
      await repo.write('new.txt', 'hello\n');
      await repo.stage('new.txt');
      await repo.git(['rm', '--quiet', 'gone.txt']);
      await repo.git(['mv', 'old.txt', 'moved.txt']);

      final run = await preCommit();

      expect(run.changes.changes, [
        FileChange(path: RepoPath('README.md'), kind: ChangeKind.modified),
        FileChange(path: RepoPath('gone.txt'), kind: ChangeKind.deleted),
        FileChange(
          path: RepoPath('moved.txt'),
          kind: ChangeKind.renamed,
          previousPath: RepoPath('old.txt'),
        ),
        FileChange(path: RepoPath('new.txt'), kind: ChangeKind.added),
      ]);
    });

    test('judges the index against HEAD', () async {
      final head = (await repo.git(['rev-parse', 'HEAD'])).trim();

      final run = await preCommit();

      expect(run.snapshot, const IndexSnapshot());
      expect(run.base, CommitSnapshot(head));
      expect(run.targetBranch, 'main');
      expect(run.label, 'index');
      expect(run.changes.isEmpty, isTrue);
    });

    test('sees a partially staged file as staged', () async {
      await repo.write('a.txt', 'staged\nunstaged\n');
      await repo.stageContent('a.txt', 'staged\n');

      final run = await preCommit();
      final files = git.files(run.snapshot);

      expect(run.changes[RepoPath('a.txt')]?.kind, ChangeKind.added);
      expect(await files.readText(RepoPath('a.txt')), 'staged\n');
    });

    test('ignores changes that are not staged', () async {
      await repo.write('README.md', 'edited on disk only\n');
      await repo.write('untracked.txt', 'x');

      expect((await preCommit()).changes.isEmpty, isTrue);
    });

    test(
      'on an unborn branch everything is added and no base exists',
      () async {
        final fresh = await TempRepo.create(initialCommit: false);
        addTearDown(fresh.dispose);
        final unborn = GitCliRepository(
          git: GitProcess(
            workingDirectory: fresh.root,
            environment: fresh.environment,
          ),
        );
        addTearDown(unborn.close);
        await fresh.stageContent('pubspec.yaml', 'name: app\n');
        await fresh.stageContent('lib/main.dart', 'void main() {}\n');

        final run = (await unborn.resolve(
          const PreCommitEntry(),
          all: false,
        )).single;

        expect(run.base, isNull);
        expect(run.changes.changes, [
          FileChange(path: RepoPath('lib/main.dart'), kind: ChangeKind.added),
          FileChange(path: RepoPath('pubspec.yaml'), kind: ChangeKind.added),
        ]);
      },
    );

    test('handles paths with spaces and non-ASCII characters', () async {
      await repo.stageContent('dir with space/ação.txt', 'ok');

      final run = await preCommit();

      expect(
        run.changes[RepoPath('dir with space/ação.txt')]?.kind,
        ChangeKind.added,
      );
    });

    test('handles paths with a quote and with a newline', () async {
      await repo.stageContent('q"uote.txt', 'quote');
      await repo.stageContent('new\nline.txt', 'newline');

      final run = await preCommit();

      expect(run.changes.changes.map((change) => change.path.value), [
        'new\nline.txt',
        'q"uote.txt',
      ]);
    }, testOn: '!windows');
  });

  group('merge in progress', () {
    setUp(() async {
      await commitFile('a.txt', 'base\n', 'a');
      await commitFile('b.txt', 'base\n', 'b');
      await commitFile('c.txt', 'base\n', 'c');
      await repo.git(['switch', '--quiet', '-c', 'feature']);
      await commitFile('b.txt', 'feature\n', 'feature b');
      await commitFile('c.txt', 'feature\n', 'feature c');
      await repo.git(['switch', '--quiet', 'main']);
      await commitFile('a.txt', 'main\n', 'main a');
      await commitFile('c.txt', 'main\n', 'main c');
      await repo.git(['merge', 'feature'], okExitCodes: {1});
      await repo.write('c.txt', 'resolved by hand\n');
      await repo.stage('c.txt');
    });

    test('layout reports the merge', () async {
      expect((await open(repo.root).layout()).mergeInProgress, isTrue);
    });

    test('keeps only paths that differ from both parents', () async {
      final run = await preCommit();

      // a.txt equals HEAD, b.txt equals the merged branch: both were
      // already validated where they came from (ADR-0007).
      expect(run.changes.changes, [
        FileChange(path: RepoPath('c.txt'), kind: ChangeKind.modified),
      ]);
    });

    test('includes a file edited by hand during the merge', () async {
      await repo.write('b.txt', 'feature, then touched\n');
      await repo.stage('b.txt');

      final run = await preCommit();

      expect(run.changes.changes.map((change) => change.path.value), [
        'b.txt',
        'c.txt',
      ]);
    });
  });

  group('rebase in progress', () {
    test('layout reports the rebase', () async {
      await commitFile('c.txt', 'base\n', 'c');
      await repo.git(['switch', '--quiet', '-c', 'feature']);
      await commitFile('c.txt', 'feature\n', 'feature c');
      await repo.git(['switch', '--quiet', 'main']);
      await commitFile('c.txt', 'main\n', 'main c');
      await repo.git(['switch', '--quiet', 'feature']);
      await repo.git(['rebase', 'main'], okExitCodes: {1});

      final layout = await open(repo.root).layout();

      expect(layout.rebaseInProgress, isTrue);
      expect(layout.mergeInProgress, isFalse);
    });
  });

  group('divergingFromWorktree', () {
    test('lists unstaged edits and deletions, sorted', () async {
      await commitFile('b.txt', 'b\n', 'b');
      await commitFile('z.txt', 'z\n', 'z');
      await repo.write('z.txt', 'edited\n');
      await repo.delete('b.txt');
      await repo.write('README.md', 'edited\n');
      await repo.stageContent('staged_only.txt', 'x');
      await repo.write('staged_only.txt', 'x');
      await repo.write('untracked.txt', 'x');

      final diverging = await git.divergingFromWorktree(const IndexSnapshot());

      expect(diverging.map((path) => path.value), [
        'README.md',
        'b.txt',
        'z.txt',
      ]);
    });

    test('includes a partially staged file', () async {
      await repo.write('a.txt', 'staged\nunstaged\n');
      await repo.stageContent('a.txt', 'staged\n');

      final diverging = await git.divergingFromWorktree(const IndexSnapshot());

      expect(diverging, {RepoPath('a.txt')});
    });

    test('compares a commit snapshot with the working tree', () async {
      final head = (await repo.git(['rev-parse', 'HEAD'])).trim();
      await repo.write('README.md', 'edited\n');
      await repo.stage('README.md');

      final diverging = await git.divergingFromWorktree(CommitSnapshot(head));

      expect(diverging, {RepoPath('README.md')});
    });
  });

  group('not yet supported', () {
    test('pre-push and ci entries arrive in 0.1.0', () {
      expect(
        () => git.resolve(
          const PrePushEntry(remote: 'origin', refs: []),
          all: false,
        ),
        throwsUnsupportedError,
      );
      expect(
        () => git.resolve(const CiEntry(baseRef: 'main'), all: false),
        throwsUnsupportedError,
      );
    });

    test('--all arrives in 0.2.0', () {
      expect(
        () => git.resolve(const PreCommitEntry(), all: true),
        throwsUnsupportedError,
      );
    });

    test('fixes arrive in 0.1.0', () {
      expect(() => git.applyFixes(const []), throwsUnsupportedError);
    });
  });

  test('files returns the same view for the same snapshot', () {
    expect(
      git.files(const IndexSnapshot()),
      same(git.files(const IndexSnapshot())),
    );
  });

  test('close may be called twice', () async {
    await git.files(const IndexSnapshot()).readText(RepoPath('README.md'));

    await git.close();
    await git.close();
  });
}

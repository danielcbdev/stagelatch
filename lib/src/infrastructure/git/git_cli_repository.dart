/// The git repository, through the git command line.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/fix.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:stagelatch/src/infrastructure/git/cat_file_batch.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:stagelatch/src/infrastructure/git/git_snapshot_files.dart';
import 'package:stagelatch/src/infrastructure/git/name_status_parser.dart';

/// [GitRepository] implemented with the git executable
/// (docs/specs/git.md).
///
/// Every command that prints a path uses `-z`. The only commands that
/// change anything are those of security rule S4.
final class GitCliRepository implements GitRepository {
  /// Creates the repository that [git] runs in.
  new({required GitProcess git}) : _git = git, _batch = CatFileBatch(git);

  final GitProcess _git;
  final CatFileBatch _batch;
  final Map<SnapshotRef, GitSnapshotFiles> _views = {};

  Future<RepoLayout>? _layout;

  @override
  Future<RepoLayout> layout() => _layout ??= _readLayout();

  Future<RepoLayout> _readLayout() async {
    // Exit code 128 is git's "fatal": here it means there is no work tree,
    // either because this is not a repository or because it is bare.
    final top = await _git.run(
      ['rev-parse', '--show-toplevel'],
      okExitCodes: {0, 128},
    );
    if (top.exitCode != 0) {
      throw UsageException(
        'Not inside a git work tree: ${_git.workingDirectory}.',
      );
    }
    final root = p.normalize(top.text.trim());
    // -C <root>: answer from the top of the work tree, so that relative
    //   answers, such as a relative core.hooksPath, resolve against it and
    //   not against whatever subdirectory the tool was started in.
    // --git-path hooks: where git looks for hooks; it already accounts for
    //   core.hooksPath and for linked worktrees.
    final result = await _git.run([
      '-C',
      root,
      'rev-parse',
      '--git-dir',
      '--git-common-dir',
      '--git-path',
      'hooks',
      '--is-shallow-repository',
    ]);
    final lines = const LineSplitter().convert(result.text);
    if (lines.length != 4) {
      throw InternalException(
        'Unexpected answer from git rev-parse: ${result.text}',
        where: 'git',
      );
    }
    String absolute(String path) => p.normalize(p.join(root, path));
    final gitDir = absolute(lines[0]);

    // --quiet: a detached HEAD is not an error worth printing; exit code 1
    //   then means "no branch".
    final branch = await _git.run(
      ['symbolic-ref', '--quiet', '--short', 'HEAD'],
      okExitCodes: {0, 1},
    );
    return RepoLayout(
      root: root,
      gitDir: gitDir,
      commonDir: absolute(lines[1]),
      hooksDir: absolute(lines[2]),
      branch: branch.exitCode == 0 ? branch.text.trim() : null,
      mergeInProgress: File(p.join(gitDir, 'MERGE_HEAD')).existsSync(),
      rebaseInProgress:
          Directory(p.join(gitDir, 'rebase-merge')).existsSync() ||
          Directory(p.join(gitDir, 'rebase-apply')).existsSync(),
      shallow: lines[3] == 'true',
    );
  }

  @override
  Future<List<ResolvedRun>> resolve(
    EntryPoint entry, {
    required bool all,
  }) async {
    if (all) throw UnsupportedError('--all arrives in 0.2.0.');
    return switch (entry) {
      PreCommitEntry() => [await _resolvePreCommit()],
      PrePushEntry() ||
      CiEntry() => throw UnsupportedError('This entry point arrives in 0.1.0.'),
    };
  }

  /// The index against `HEAD` (docs/specs/git.md, section 4.1).
  Future<ResolvedRun> _resolvePreCommit() async {
    final layout = await this.layout();
    // --verify --quiet: print the commit id, or nothing with exit code 1
    //   when HEAD does not name a commit yet (an unborn branch).
    final head = await _git.run(
      ['rev-parse', '--verify', '--quiet', 'HEAD^{commit}'],
      okExitCodes: {0, 1},
    );
    final headSha = head.exitCode == 0 ? head.text.trim() : null;

    // --cached: the index against HEAD; against the empty tree when HEAD
    //   does not exist yet.
    // --name-status: one status letter per path, no patch.
    // -M: pair a deleted and an added path into a rename.
    final diff = await _git.run([
      'diff',
      '--cached',
      '--name-status',
      '-z',
      '-M',
    ]);
    var changes = parseNameStatus(diff.nulSeparated);
    if (layout.mergeInProgress && headSha != null) {
      final manual = await _differingFromEveryParent(layout, headSha);
      changes = [
        for (final change in changes)
          if (manual.contains(change.path)) change,
      ];
    }
    return ResolvedRun(
      snapshot: const IndexSnapshot(),
      base: headSha == null ? null : CommitSnapshot(headSha),
      changes: ChangeSet(changes),
      targetBranch: layout.branch,
      label: 'index',
    );
  }

  /// ADR-0007: during a merge only paths that differ from every parent
  /// count. Those are conflict resolutions and manual edits; a path taken
  /// unchanged from either side was validated on its own branch.
  Future<Set<RepoPath>> _differingFromEveryParent(
    RepoLayout layout,
    String headSha,
  ) async {
    final mergeHead = File(p.join(layout.gitDir, 'MERGE_HEAD'));
    final parents = [
      headSha,
      ...const LineSplitter()
          .convert(await mergeHead.readAsString())
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty),
    ];
    Set<RepoPath>? common;
    for (final parent in parents) {
      // --no-renames: both sides of a rename as plain paths, so that sets
      //   of paths can be intersected.
      final result = await _git.run([
        'diff',
        '--cached',
        '--name-only',
        '-z',
        '--no-renames',
        parent,
      ]);
      final paths = result.nulSeparated.map(RepoPath.new).toSet();
      common = common == null ? paths : common.intersection(paths);
    }
    return common ?? const {};
  }

  @override
  SnapshotFiles files(SnapshotRef ref) => _views.putIfAbsent(
    ref,
    () => GitSnapshotFiles(git: _git, batch: _batch, ref: ref),
  );

  @override
  Future<Set<RepoPath>> divergingFromWorktree(SnapshotRef ref) async {
    // Without a commit, git diff compares the index with the working tree;
    // with one, the commit with the working tree.
    // --name-only -z: paths only, NUL-separated.
    // --no-renames: both sides of a rename as plain paths.
    final result = await _git.run([
      'diff',
      '--name-only',
      '-z',
      '--no-renames',
      if (ref case CommitSnapshot(:final sha)) sha,
    ]);
    final paths = result.nulSeparated.map(RepoPath.new).toList()..sort();
    return paths.toSet();
  }

  @override
  Future<List<AppliedFix>> applyFixes(List<Fix> fixes) async {
    throw UnsupportedError('Fixes arrive in 0.1.0.');
  }

  @override
  Future<void> close() => _batch.close();
}

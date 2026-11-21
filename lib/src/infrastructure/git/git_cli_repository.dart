/// The git repository, through the git command line.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    final runs = switch (entry) {
      PreCommitEntry() => [await _resolvePreCommit()],
      PrePushEntry() => await _resolvePrePush(entry),
      CiEntry() => [await _resolveCi(entry)],
    };
    if (!all) return runs;
    // `--all`: the base, the target branch and the label are those of the
    // run without it, because rules that compare with the base still need
    // them; only the changeset changes (docs/specs/git.md, section 4.4).
    return [
      for (final run in runs)
        ResolvedRun(
          snapshot: run.snapshot,
          base: run.base,
          changes: await _everyRegularFile(run.snapshot),
          targetBranch: run.targetBranch,
          label: run.label,
        ),
    ];
  }

  /// Every regular file of [snapshot] as an added file. Symlinks and
  /// submodule entries are not content a rule can judge, so they are left
  /// out, as they are from any other changeset.
  Future<ChangeSet> _everyRegularFile(SnapshotRef snapshot) async => ChangeSet([
    for (final entry in await files(snapshot).list())
      if (entry.mode.isFile)
        FileChange(path: entry.path, kind: ChangeKind.added),
  ]);

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

  /// The pull request's head against its fork point (docs/specs/git.md,
  /// section 4.3).
  Future<ResolvedRun> _resolveCi(CiEntry entry) async {
    final base = await _mergeBase(entry.baseRef, entry.headRef);
    // ^{commit}: the commit a tag or branch name points at.
    final head = (await _git.run([
      'rev-parse',
      '--verify',
      '${entry.headRef}^{commit}',
    ])).text.trim();
    // --name-status -z -M: as for pre-commit, between two commits.
    final diff = await _git.run([
      'diff',
      '--name-status',
      '-z',
      '-M',
      base,
      head,
    ]);
    final target = _branchName(entry.baseRef);
    return ResolvedRun(
      snapshot: CommitSnapshot(head),
      base: CommitSnapshot(base),
      changes: ChangeSet(parseNameStatus(diff.nulSeparated)),
      targetBranch: target,
      label: target,
    );
  }

  @override
  Future<ResolvedRun> resolveAgainstIndex({String? baseRef}) async {
    final resolved = baseRef ?? await _whyBaseRef();
    if (resolved == null) {
      throw const UsageException('Cannot determine a base. Pass --base <ref>.');
    }
    final base = await _mergeBase(resolved, 'HEAD');
    final layout = await this.layout();
    // --cached: the index against the merge base (docs/specs/git.md, 4.3.1).
    final diff = await _git.run([
      'diff',
      '--cached',
      '--name-status',
      '-z',
      '-M',
      base,
    ]);
    return ResolvedRun(
      snapshot: const IndexSnapshot(),
      base: CommitSnapshot(base),
      changes: ChangeSet(parseNameStatus(diff.nulSeparated)),
      targetBranch: layout.branch,
      label: 'index',
    );
  }

  /// The merge base of [baseRef] and [headRef], or the usage error `ci`
  /// and `why` share when there is none (ADR-0007).
  Future<String> _mergeBase(String baseRef, String headRef) async {
    // Exit 1: no common ancestor. Exit 128: a ref git does not know, as
    // when a shallow clone never fetched the base branch. Either way the
    // diff would be wrong, so nothing is analyzed.
    final mergeBase = await _git.run(
      ['merge-base', baseRef, headRef],
      okExitCodes: {0, 1, 128},
    );
    if (mergeBase.exitCode != 0) {
      throw UsageException(
        'Cannot find a merge base between $baseRef and '
        '$headRef. If this is a shallow clone, fetch full history '
        '(actions/checkout: fetch-depth: 0).',
      );
    }
    return mergeBase.text.trim();
  }

  /// Upstream of the current branch, else `refs/remotes/origin/HEAD`.
  Future<String?> _whyBaseRef() async {
    final layout = await this.layout();
    final branch = layout.branch;
    if (branch != null) {
      // --verify --quiet: the upstream commit, or nothing when unset.
      final upstream = await _git.run(
        ['rev-parse', '--verify', '--quiet', '$branch@{upstream}'],
        okExitCodes: {0, 1, 128},
      );
      if (upstream.exitCode == 0) {
        final value = upstream.text.trim();
        if (value.isNotEmpty) return value;
      }
    }
    final remoteHead = await _git.run(
      ['symbolic-ref', '--quiet', 'refs/remotes/origin/HEAD'],
      okExitCodes: {0, 1, 128},
    );
    if (remoteHead.exitCode == 0) {
      final value = remoteHead.text.trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  /// [ref] without a leading `origin/` or `refs/heads/`.
  static String _branchName(String ref) {
    for (final prefix in const ['refs/heads/', 'origin/']) {
      if (ref.startsWith(prefix)) return ref.substring(prefix.length);
    }
    return ref;
  }

  /// One run per pushed branch (docs/specs/git.md, section 4.2).
  Future<List<ResolvedRun>> _resolvePrePush(PrePushEntry entry) async {
    final runs = <ResolvedRun>[];
    for (final ref in entry.refs) {
      // A deletion has nothing to validate, and a tag is not a branch.
      if (_isZero(ref.localSha)) continue;
      if (!ref.remoteRef.startsWith('refs/heads/')) continue;
      if (!await _hasCommit(ref.localSha)) {
        throw UsageException(
          'Unknown commit "${ref.localSha}" in the pre-push input.',
        );
      }
      final base = await _pushBase(entry.remote, ref);
      final List<FileChange> changes;
      if (base == null) {
        // The empty tree: every file of the pushed commit is new. Listing
        // the commit avoids naming the empty tree, whose id depends on the
        // repository's object format.
        changes = [
          for (final file in await files(CommitSnapshot(ref.localSha)).list())
            FileChange(path: file.path, kind: ChangeKind.added),
        ];
      } else {
        // --name-status -z -M: as for pre-commit, between two commits.
        final diff = await _git.run([
          'diff',
          '--name-status',
          '-z',
          '-M',
          base,
          ref.localSha,
        ]);
        changes = parseNameStatus(diff.nulSeparated);
      }
      final branch = ref.remoteRef.substring('refs/heads/'.length);
      runs.add(
        ResolvedRun(
          snapshot: CommitSnapshot(ref.localSha),
          base: base == null ? null : CommitSnapshot(base),
          changes: ChangeSet(changes),
          targetBranch: branch,
          label: branch,
        ),
      );
    }
    return runs;
  }

  /// The commit a pushed ref is compared with, or null for the empty tree.
  Future<String?> _pushBase(String remote, PushedRef ref) async {
    if (!_isZero(ref.remoteSha) && await _hasCommit(ref.remoteSha)) {
      return ref.remoteSha;
    }
    // A new branch, or a remote sha this clone has not fetched: the newest
    // commit of the pushed history that some branch of the remote already
    // contains. --format=%(objectname): one sha per ref, nothing else.
    final refs = await _git.run([
      'for-each-ref',
      '--format=%(objectname)',
      'refs/remotes/$remote/',
    ]);
    final known = const LineSplitter()
        .convert(refs.text)
        .where((line) => line.isNotEmpty)
        .toList();
    if (known.isEmpty) return null;
    // With several commits after the first, merge-base answers for the
    // first against any of the others. Exit 1: no common ancestor.
    final mergeBase = await _git.run(
      ['merge-base', ref.localSha, ...known],
      okExitCodes: {0, 1},
    );
    return mergeBase.exitCode == 0 ? mergeBase.text.trim() : null;
  }

  Future<bool> _hasCommit(String sha) async {
    // -e: exit 0 when the object exists and is valid, silently.
    final result = await _git.run(
      ['cat-file', '-e', '$sha^{commit}'],
      okExitCodes: {0, 1, 128},
    );
    return result.exitCode == 0;
  }

  static bool _isZero(String sha) =>
      sha.isNotEmpty && sha.replaceAll('0', '').isEmpty;

  @override
  Future<PrePushEntry> synthesizePrePush({String? remote}) async {
    // --short: the branch name without refs/heads/; exit 1 when detached.
    final branch = await _git.run(
      ['symbolic-ref', '--quiet', '--short', 'HEAD'],
      okExitCodes: {0, 1, 128},
    );
    final name = branch.text.trim();
    if (branch.exitCode != 0 || name.isEmpty) {
      return PrePushEntry(remote: remote ?? 'origin', refs: const []);
    }
    final head = (await _git.run(['rev-parse', 'HEAD'])).text.trim();
    // The upstream as configured: branch.<name>.remote and .merge.
    final configuredRemote = await _config('branch.$name.remote');
    final merge = await _config('branch.$name.merge');
    // --verify --quiet: the upstream's commit, or nothing when there is no
    // upstream or it was never fetched.
    final upstream = await _git.run(
      ['rev-parse', '--verify', '--quiet', '$name@{upstream}'],
      okExitCodes: {0, 1, 128},
    );
    final upstreamSha = upstream.exitCode == 0 ? upstream.text.trim() : '';
    return PrePushEntry(
      remote: remote ?? configuredRemote ?? 'origin',
      refs: [
        PushedRef(
          localRef: 'refs/heads/$name',
          localSha: head,
          remoteRef: merge ?? 'refs/heads/$name',
          remoteSha: upstreamSha.isEmpty ? '0' * head.length : upstreamSha,
        ),
      ],
    );
  }

  /// The value of the git config [key], or null when unset.
  Future<String?> _config(String key) async {
    // --get: one value; exit 1 when the key is not set.
    final result = await _git.run(
      ['config', '--get', key],
      okExitCodes: {0, 1},
    );
    final value = result.text.trim();
    return result.exitCode == 0 && value.isNotEmpty ? value : null;
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
  Future<Set<RepoPath>> divergentAmong(
    SnapshotRef ref,
    Set<RepoPath> paths,
  ) async {
    final diverging = await divergingFromWorktree(ref);
    final result = {
      for (final path in paths)
        if (diverging.contains(path)) path,
    };

    // The rest cannot differ from a snapshot file, so the only ones left to
    // look at are the paths the snapshot lacks (ADR-0018, rule 2): those
    // that exist on disk as a regular file, and not through a link.
    final snapshot = files(ref);
    final root = (await layout()).root;
    final present = <RepoPath>[];
    for (final path in [...paths]..sort()) {
      if (result.contains(path) || await snapshot.entry(path) != null) {
        continue;
      }
      final onDisk = p.joinAll([root, ...path.value.split('/')]);
      if (FileSystemEntity.typeSync(onDisk, followLinks: false) ==
          FileSystemEntityType.file) {
        present.add(path);
      }
    }
    if (present.isEmpty) return result;

    // Git would track the ones that are not ignored: untracked files that a
    // commit would pick up. One process answers for all of them.
    final ignored = await _ignored(present);
    return result..addAll(present.where((path) => !ignored.contains(path)));
  }

  /// Which of [paths] `git check-ignore` reports as ignored.
  Future<Set<RepoPath>> _ignored(List<RepoPath> paths) async {
    // check-ignore reads paths relative to the directory git runs in, which
    // is not always the top of the work tree.
    // --show-prefix: where that directory is under the top, with a final
    //   slash, or empty at the top.
    final prefix = (await _git.run(['rev-parse', '--show-prefix'])).text.trim();
    final up =
        '../' *
        (prefix.isEmpty
            ? 0
            : prefix.split('/').where((s) => s.isNotEmpty).length);
    final input = BytesBuilder(copy: false);
    for (final path in paths) {
      input
        ..add(utf8.encode('$up${path.value}'))
        ..addByte(0);
    }
    // --stdin: the paths come from us, so that their number is not bounded
    //   by the length of a command line.
    // -z: NUL-separated input and output.
    // Exit code 0: something is ignored. 1: nothing is. Both are answers.
    final result = await _git.run(
      ['check-ignore', '--stdin', '-z'],
      stdin: input.takeBytes(),
      okExitCodes: {0, 1},
    );
    return {
      for (final line in result.nulSeparated)
        if (line.startsWith(up)) RepoPath(line.substring(up.length)),
    };
  }

  /// Writes [fixes] to the index without losing unstaged work
  /// (ADR-0002, docs/specs/git.md section 6). Only the mutations of
  /// security rule S4 are used: `hash-object -w`, `update-index
  /// --index-info` and `checkout-index`.
  @override
  Future<List<AppliedFix>> applyFixes(List<Fix> fixes) async {
    if (fixes.isEmpty) return const [];
    final sorted = [...fixes]..sort((a, b) => a.path.compareTo(b.path));
    final paths = [for (final fix in sorted) fix.path.value];
    final index = files(const IndexSnapshot());

    // Step 1, before anything is written: which of these paths already
    // differ from the working tree. Their working tree copy holds unstaged
    // work and must not be overwritten.
    // --name-only -z: NUL-separated paths only. --no-renames: plain paths.
    final diverging = (await _git.run([
      'diff',
      '--name-only',
      '-z',
      '--no-renames',
      '--',
      ...paths,
    ])).nulSeparated.toSet();

    // Step 2: one blob per fix. --stdin: the content comes from us.
    // --no-filters: the content came from the index, so it is already in
    // repository form; filters would convert it a second time.
    final records = BytesBuilder(copy: false);
    for (final fix in sorted) {
      final entry = await index.entry(fix.path);
      if (entry == null || !entry.mode.isFile) {
        throw InternalException(
          'Cannot fix ${fix.path.value}: it is not a file in the index.',
          where: 'git',
        );
      }
      final blob = await _git.run([
        'hash-object',
        '-w',
        '--stdin',
        '--no-filters',
      ], stdin: utf8.encode(fix.content));
      final mode = entry.mode == FileMode.executable ? '100755' : '100644';
      records
        ..add(utf8.encode('$mode ${blob.text.trim()}\t${fix.path.value}'))
        ..addByte(0);
    }

    // Step 3: every entry in one atomic update-index call, so the index is
    // never left half-updated by us. A held index.lock fails here, before
    // anything changed; git's message names the lock.
    // -z --index-info: NUL-terminated `<mode> <blob>\t<path>` records.
    await _git.run([
      'update-index',
      '-z',
      '--index-info',
    ], stdin: records.takeBytes());
    _views.remove(const IndexSnapshot());

    // Step 4: refresh the working tree copies that had no unstaged work,
    // through git, so line-ending and filter configuration apply.
    final refresh = [
      for (final path in paths)
        if (!diverging.contains(path)) path,
    ];
    var refreshed = refresh.isNotEmpty;
    if (refreshed) {
      // --force: overwrite the existing working tree file.
      final result = await _git.run(
        ['checkout-index', '--force', '--', ...refresh],
        okExitCodes: const {0, 1, 128},
      );
      // The commit content is already correct; a failure here only leaves
      // the working tree copy as it was.
      refreshed = result.exitCode == 0;
    }
    return [
      for (final fix in sorted)
        AppliedFix(
          rule: fix.rule,
          path: fix.path,
          worktreeUpdated: refreshed && !diverging.contains(fix.path.value),
        ),
    ];
  }

  @override
  Future<void> close() => _batch.close();
}

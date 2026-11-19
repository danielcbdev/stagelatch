import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/fix.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

import 'fake_snapshot_files.dart';

/// An in-memory [GitRepository] with one index and any number of commits.
final class FakeGitRepository implements GitRepository {
  /// Creates a repository whose index holds [index].
  ///
  /// By default it resolves every entry point to one run of the index
  /// against no base, with [changes]. Pass [_runs] to decide exactly what
  /// `resolve` returns, and [_commits] for the content of commit snapshots.
  new({
    Map<String, Object> index = const {},
    this._commits = const {},
    ChangeSet? changes,
    this.targetBranch,
    this._runs,
    this._diverging = const {},
  }) : index = {...index},
       _changes = changes ?? ChangeSet(const []);

  /// The content of the index. Applying a fix changes it.
  final Map<String, Object> index;

  /// The target branch of the default run.
  final String? targetBranch;

  final Map<String, Map<String, Object>> _commits;
  final ChangeSet _changes;
  final List<ResolvedRun>? _runs;
  final Set<String> _diverging;

  /// Every fix handed to [applyFixes], in order.
  final List<Fix> appliedFixes = [];

  /// The `all` flag of the most recent [resolve] call.
  bool? lastResolveAll;

  /// Whether [close] was called.
  bool closed = false;

  @override
  Future<RepoLayout> layout() =>
      throw UnimplementedError('FakeGitRepository has no layout.');

  @override
  Future<List<ResolvedRun>> resolve(
    EntryPoint entry, {
    required bool all,
  }) async {
    lastResolveAll = all;
    return _runs ??
        [
          ResolvedRun(
            snapshot: const IndexSnapshot(),
            base: null,
            changes: _changes,
            targetBranch: targetBranch,
            label: 'index',
          ),
        ];
  }

  @override
  SnapshotFiles files(SnapshotRef ref) => switch (ref) {
    // A new view on every call, so that a fix applied to the index is
    // visible to whoever reopens the snapshot.
    IndexSnapshot() => FakeSnapshotFiles(index),
    CommitSnapshot(:final sha) => FakeSnapshotFiles(
      _commits[sha] ?? (throw StateError('No commit $sha in the fake.')),
    ),
  };

  @override
  Future<Set<RepoPath>> divergingFromWorktree(SnapshotRef ref) async =>
      _diverging.map(RepoPath.new).toSet();

  @override
  Future<List<AppliedFix>> applyFixes(List<Fix> fixes) async {
    appliedFixes.addAll(fixes);
    for (final fix in fixes) {
      index[fix.path.value] = fix.content;
    }
    return [
      for (final fix in fixes)
        AppliedFix(
          rule: fix.rule,
          path: fix.path,
          worktreeUpdated: !_diverging.contains(fix.path.value),
        ),
    ];
  }

  @override
  Future<void> close() async => closed = true;
}

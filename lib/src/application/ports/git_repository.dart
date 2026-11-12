/// The port through which use cases reach the git repository.
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/fix.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// Names a snapshot: the index, or one commit.
@immutable
sealed class SnapshotRef {
  const new();
}

/// The index: what the next commit will contain.
final class IndexSnapshot extends SnapshotRef {
  /// Creates the reference.
  const new();

  @override
  bool operator ==(Object other) => other is IndexSnapshot;

  @override
  int get hashCode => (IndexSnapshot).hashCode;

  @override
  String toString() => 'index';
}

/// The tree of one commit.
final class CommitSnapshot extends SnapshotRef {
  /// Creates a reference to the commit [sha].
  const new(this.sha);

  /// The full object id of the commit.
  final String sha;

  @override
  bool operator ==(Object other) => other is CommitSnapshot && other.sha == sha;

  @override
  int get hashCode => sha.hashCode;

  @override
  String toString() => sha;
}

/// One thing to judge: a snapshot, what it is compared with, and what
/// changed between the two (ADR-0007).
final class ResolvedRun {
  /// Creates a resolved run.
  const new({
    required this.snapshot,
    required this.base,
    required this.changes,
    required this.targetBranch,
    required this.label,
  });

  /// The content being judged.
  final SnapshotRef snapshot;

  /// The other side of [changes]; null when there is none, as on the first
  /// commit of a repository.
  final SnapshotRef? base;

  /// The paths that differ between [base] and [snapshot].
  final ChangeSet changes;

  /// The branch the change is headed for, or null when unknown.
  final String? targetBranch;

  /// A short name for reports: `index`, or the pushed branch.
  final String label;
}

/// Where the parts of the repository are, and what state it is in.
final class RepoLayout {
  /// Creates a layout.
  const new({
    required this.root,
    required this.gitDir,
    required this.commonDir,
    required this.hooksDir,
    required this.branch,
    required this.mergeInProgress,
    required this.rebaseInProgress,
    required this.shallow,
  });

  /// The top of the work tree, as an absolute path.
  final String root;

  /// The git directory of this work tree. In a linked worktree it is a
  /// directory under [commonDir].
  final String gitDir;

  /// The git directory shared by every worktree of the repository.
  final String commonDir;

  /// Where git looks for hooks: `core.hooksPath` when it is set, else
  /// `hooks` under [commonDir].
  final String hooksDir;

  /// The current branch, or null on a detached `HEAD`.
  final String? branch;

  /// Whether a merge is waiting to be committed.
  final bool mergeInProgress;

  /// Whether a rebase is under way.
  final bool rebaseInProgress;

  /// Whether the repository is a shallow clone.
  final bool shallow;
}

/// The record of one fix that was written to the index (ADR-0002).
@immutable
final class AppliedFix {
  /// Creates the record.
  const new({
    required this.rule,
    required this.path,
    required this.worktreeUpdated,
  });

  /// The rule whose finding was fixed.
  final RuleId rule;

  /// The file that was replaced in the index.
  final RepoPath path;

  /// Whether the working tree copy was refreshed too. False when the file
  /// had unstaged changes, which are never overwritten.
  final bool worktreeUpdated;

  @override
  bool operator ==(Object other) =>
      other is AppliedFix &&
      other.rule == rule &&
      other.path == path &&
      other.worktreeUpdated == worktreeUpdated;

  @override
  int get hashCode => Object.hash(rule, path, worktreeUpdated);

  @override
  String toString() => 'AppliedFix($rule, $path)';
}

/// Everything the tool asks of git.
abstract interface class GitRepository {
  /// Where the repository's parts are. Throws `UsageException` outside a
  /// git work tree.
  Future<RepoLayout> layout();

  /// What [entry] asks to be judged: one run for pre-commit and ci, one per
  /// pushed branch for pre-push. With [all], every file of the snapshot
  /// counts as changed.
  Future<List<ResolvedRun>> resolve(EntryPoint entry, {required bool all});

  /// A read-only view of the snapshot [ref].
  SnapshotFiles files(SnapshotRef ref);

  /// The paths whose content in [ref] differs from the working tree,
  /// deletions included, sorted. This is the overlay set of ADR-0001.
  Future<Set<RepoPath>> divergingFromWorktree(SnapshotRef ref);

  /// Writes [fixes] to the index and returns what was applied. Only valid
  /// when the snapshot being judged is the index.
  Future<List<AppliedFix>> applyFixes(List<Fix> fixes);

  /// Ends every git process this repository started.
  Future<void> close();
}

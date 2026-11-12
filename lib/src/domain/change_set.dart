/// What changed between a snapshot and its base.
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// How a path differs between the base and the snapshot.
enum ChangeKind {
  /// The path exists only in the snapshot.
  added,

  /// The path exists on both sides with different content.
  modified,

  /// The path exists only in the base.
  deleted,

  /// The path is new and git paired it with a path removed from the base.
  renamed,

  /// The entry changed type, for example from a file to a symlink.
  typeChanged,
}

/// One changed path.
@immutable
final class FileChange {
  /// Creates a change of [kind] at [path].
  ///
  /// [previousPath] is the path in the base. It is required for
  /// [ChangeKind.renamed] and forbidden for every other kind.
  const new({required this.path, required this.kind, this.previousPath})
    : assert(
        (kind == ChangeKind.renamed) == (previousPath != null),
        'previousPath is required for a rename and forbidden otherwise',
      );

  /// The path in the snapshot; for [ChangeKind.deleted], the path it had.
  final RepoPath path;

  /// How the path changed.
  final ChangeKind kind;

  /// Where a renamed file was in the base; null unless [kind] is a rename.
  final RepoPath? previousPath;

  @override
  bool operator ==(Object other) =>
      other is FileChange &&
      other.path == path &&
      other.kind == kind &&
      other.previousPath == previousPath;

  @override
  int get hashCode => Object.hash(path, kind, previousPath);

  @override
  String toString() => previousPath == null
      ? '${kind.name} $path'
      : '${kind.name} $previousPath -> $path';
}

/// The set of paths that changed between the base and the snapshot.
///
/// This is what makes the tool change-aware: every rule decides whether to
/// run, and what to look at, from here.
final class ChangeSet {
  /// Creates a changeset from [changes], in any order.
  ///
  /// Throws [ArgumentError] when a path appears more than once.
  factory(Iterable<FileChange> changes) {
    final sorted = [...changes]..sort((a, b) => a.path.compareTo(b.path));
    final byPath = {for (final change in sorted) change.path: change};
    if (byPath.length != sorted.length) {
      throw ArgumentError('A path appears more than once in the changeset.');
    }
    return ChangeSet._(List.unmodifiable(sorted), byPath);
  }

  const new _(this.changes, this._byPath);

  /// Every change, sorted by path. Unmodifiable.
  final List<FileChange> changes;

  final Map<RepoPath, FileChange> _byPath;

  /// The changes whose path still exists in the snapshot: everything except
  /// [ChangeKind.deleted]. Content rules iterate over this.
  Iterable<FileChange> get present =>
      changes.where((change) => change.kind != ChangeKind.deleted);

  /// Whether nothing changed.
  bool get isEmpty => changes.isEmpty;

  /// The number of changed paths.
  int get length => changes.length;

  /// The change at [path] in the snapshot, or null when it did not change.
  ///
  /// A rename is found by its new path only.
  FileChange? operator [](RepoPath path) => _byPath[path];
}

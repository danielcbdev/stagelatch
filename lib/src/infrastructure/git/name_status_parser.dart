/// Parsing of `git diff --name-status -z` output.
library;

import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// What the user is told when the index still has conflicted entries.
const String unmergedIndexMessage =
    'The index has unmerged paths; resolve conflicts first.';

/// Turns the NUL-separated fields of `git diff --name-status -z` into
/// changes, in the order git printed them.
///
/// The output is a flat sequence: a status, then one path, or two paths
/// (old, then new) for a rename or copy. A rename or copy status carries a
/// similarity score after its letter, as in `R087`.
///
/// Throws [UsageException] for an unmerged entry, and [InternalException]
/// for a status this tool does not know or for truncated output.
List<FileChange> parseNameStatus(List<String> fields) {
  final changes = <FileChange>[];
  var index = 0;

  RepoPath nextPath() {
    if (index >= fields.length) {
      throw const InternalException(
        'git diff output ended in the middle of a record.',
        where: 'git',
      );
    }
    return RepoPath(fields[index++]);
  }

  while (index < fields.length) {
    final status = fields[index++];
    switch (status.isEmpty ? '' : status[0]) {
      case 'A':
        changes.add(FileChange(path: nextPath(), kind: ChangeKind.added));
      case 'M':
        changes.add(FileChange(path: nextPath(), kind: ChangeKind.modified));
      case 'D':
        changes.add(FileChange(path: nextPath(), kind: ChangeKind.deleted));
      case 'T':
        changes.add(FileChange(path: nextPath(), kind: ChangeKind.typeChanged));
      case 'R':
        final from = nextPath();
        changes.add(
          FileChange(
            path: nextPath(),
            kind: ChangeKind.renamed,
            previousPath: from,
          ),
        );
      case 'C':
        // Copy detection is never requested; if git reports one anyway,
        // the new path is simply a new file.
        nextPath();
        changes.add(FileChange(path: nextPath(), kind: ChangeKind.added));
      case 'U':
        throw const UsageException(unmergedIndexMessage);
      default:
        throw InternalException(
          'Unexpected status "$status" in git diff output.',
          where: 'git',
        );
    }
  }
  return changes;
}

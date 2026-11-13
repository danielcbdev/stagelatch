/// The port through which use cases reach files of the working tree.
library;

import 'package:stagelatch/src/domain/repo_path.dart';

/// Reads and writes text files of the working tree by repository path.
///
/// Checks never see this: they judge the snapshot (ADR-0001). It exists
/// for the few things that are about the working tree by nature, such as
/// writing `stagelatch.yaml` on `init`, or reading a config that has not
/// been staged yet.
abstract interface class WorkingTree {
  /// The UTF-8 text of the file at [path], or null when there is no such
  /// file.
  Future<String?> readText(RepoPath path);

  /// Writes [content] to [path], creating parent directories.
  Future<void> writeText(RepoPath path, String content);

  /// Whether a file exists at [path].
  Future<bool> exists(RepoPath path);
}

/// The git hooks this version can install.
library;

/// A hook git can run, and the file name it looks up.
enum HookName {
  /// `git commit`.
  preCommit('pre-commit'),

  /// `git push`.
  prePush('pre-push');

  new(this.fileName);

  /// The file name inside the hooks directory.
  final String fileName;
}

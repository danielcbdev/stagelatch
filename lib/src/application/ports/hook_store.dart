/// The port through which hook scripts are read and written.
library;

import 'package:stagelatch/src/application/hooks/hook_name.dart';

/// Stores hook scripts and the backups made before replacing one.
///
/// Every path it writes is inside the hooks directory git reported
/// (security rule S3). Files whose name ends in `.sample` are not hooks
/// and are never read or written here.
abstract interface class HookStore {
  /// The path of [hook], whether or not the file exists.
  String pathOf(HookName hook);

  /// The text of [hook], or null when there is no such file.
  ///
  /// A `.sample` file of the same name does not count.
  Future<String?> read(HookName hook);

  /// Writes [content] as [hook], creating the directory if needed.
  ///
  /// The bytes are written as given. Line endings are not translated.
  Future<void> write(HookName hook, String content);

  /// Removes [hook] if it exists. Does nothing when it does not.
  Future<void> delete(HookName hook);

  /// Copies [hook] to the next backup name and returns that path.
  ///
  /// The first backup is `<hook>.stagelatch-backup`. Each later one adds
  /// `.1`, `.2`, and so on.
  Future<String> backup(HookName hook);

  /// Copies the newest backup of [hook] back over the hook file.
  ///
  /// The newest backup is the one with the highest numeric suffix, or the
  /// unnumbered one when no numbered backup exists. Returns the backup
  /// path, or null when there is no backup.
  Future<String?> restoreLatestBackup(HookName hook);

  /// Whether the hooks directory is inside the work tree and git tracks
  /// at least one file in it.
  ///
  /// A tracked directory means the installed script will show up as a
  /// change. The default git hooks directory, under `.git`, is not tracked.
  Future<bool> get directoryIsTracked;
}

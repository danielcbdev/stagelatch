/// What installing or removing one hook did.
library;

import 'package:stagelatch/src/application/hooks/hook_name.dart';

/// The outcome of one hook in an install or uninstall.
///
/// [path] is where the hook file is, or would be. The command layer turns
/// each subtype into one line of output.
sealed class HookAction {
  const new(this.hook, this.path);

  /// The hook this action is about.
  final HookName hook;

  /// The path of the hook file.
  final String path;
}

/// A script was written where no hook file existed.
final class HookInstalled extends HookAction {
  /// Creates the action.
  const new(super.hook, super.path);
}

/// A managed script whose text differed was overwritten.
final class HookUpdated extends HookAction {
  /// Creates the action.
  const new(super.hook, super.path);
}

/// A managed script already had the current text, so nothing was written.
final class HookUpToDate extends HookAction {
  /// Creates the action.
  const new(super.hook, super.path);
}

/// An unmanaged hook was left in place because `--force` was not given.
final class HookRefused extends HookAction {
  /// Creates the action.
  const new(super.hook, super.path);
}

/// An unmanaged hook was backed up and replaced. Only with `--force`.
final class HookReplaced extends HookAction {
  /// Creates the action. [backup] is the path of the copy that was kept.
  const new(super.hook, super.path, this.backup);

  /// Where the previous script was copied.
  final String backup;
}

/// A managed script was deleted.
final class HookRemoved extends HookAction {
  /// Creates the action.
  const new(super.hook, super.path);
}

/// A backup was written back after a managed script was removed.
final class HookRestored extends HookAction {
  /// Creates the action. [backup] is the copy that was restored.
  const new(super.hook, super.path, this.backup);

  /// The backup that was copied back, the newest one.
  final String backup;
}

/// There was no managed script for this hook.
final class HookNotFound extends HookAction {
  /// Creates the action.
  const new(super.hook, super.path);
}

/// Turns hook actions into the lines of docs/specs/cli.md sections 3.2 and 3.3.
library;

import 'package:stagelatch/src/application/hooks/hook_action.dart';
import 'package:stagelatch/src/cli/io.dart';

/// Prints [actions] and returns 64 when any hook was refused.
int reportInstall(Io io, List<HookAction> actions) {
  var refused = false;
  for (final action in actions) {
    switch (action) {
      case HookInstalled():
        io.stdout.writeln(
          'Installed ${action.hook.fileName} hook at ${action.path}.',
        );
      case HookUpdated():
        io.stdout.writeln(
          'Updated ${action.hook.fileName} hook at ${action.path}.',
        );
      case HookUpToDate():
        io.stdout.writeln(
          '${action.hook.fileName} hook is already up to date.',
        );
      case HookReplaced(:final backup):
        io.stdout.writeln(
          'Replaced ${action.hook.fileName} hook at ${action.path}; '
          'backup saved to $backup.',
        );
      case HookRefused():
        refused = true;
        _refused(io, action);
      case HookRemoved() || HookRestored() || HookNotFound():
        break;
    }
  }
  return refused ? 64 : 0;
}

/// Prints [actions] for `uninstall`. Always succeeds.
void reportUninstall(Io io, List<HookAction> actions) {
  for (final action in actions) {
    switch (action) {
      case HookRemoved():
        io.stdout.writeln('Removed ${action.hook.fileName} hook.');
      case HookRestored(:final backup):
        io.stdout.writeln(
          'Restored ${action.hook.fileName} hook from $backup.',
        );
      case HookNotFound():
        io.stdout.writeln('No managed ${action.hook.fileName} hook found.');
      case HookInstalled() ||
          HookUpdated() ||
          HookUpToDate() ||
          HookReplaced() ||
          HookRefused():
        break;
    }
  }
}

void _refused(Io io, HookRefused action) {
  final name = action.hook.fileName;
  io.stderr.writeln(
    'A $name hook that stagelatch does not manage already exists at '
    '${action.path}.',
  );
  io.stderr.writeln(
    'Add this line to it, or re-run with --force to replace it '
    '(a backup is kept):',
  );
  io.stderr.write('  stagelatch run $name ');
  io.stderr.writeln(r'"$@"');
}

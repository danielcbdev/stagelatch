/// Installs and removes the managed hook scripts (docs/specs/git.md section 8).
library;

import 'package:stagelatch/src/application/hooks/hook_action.dart';
import 'package:stagelatch/src/application/hooks/hook_name.dart';
import 'package:stagelatch/src/application/hooks/hook_script.dart';
import 'package:stagelatch/src/application/ports/hook_store.dart';

/// Applies the install matrix of docs/specs/git.md section 8.
///
/// A hook without the managed marker is never overwritten or removed
/// unless [install] is called with `force: true`, and then only after a
/// backup (security rule S12).
final class HookInstaller {
  /// Creates an installer over the given store.
  const new(this._store);

  final HookStore _store;

  /// Installs [hooks].
  ///
  /// The result is in [HookName] order, one action per requested hook.
  /// An unmanaged hook becomes [HookRefused] unless [force] is true, in
  /// which case it is backed up and becomes [HookReplaced].
  Future<List<HookAction>> install(
    Set<HookName> hooks, {
    required bool force,
  }) async {
    final actions = <HookAction>[];
    for (final hook in _inOrder(hooks)) {
      actions.add(await _installOne(hook, force: force));
    }
    return actions;
  }

  /// Removes every managed hook and restores its newest backup.
  ///
  /// One or two actions per [HookName], in enum order. An unmanaged hook,
  /// or a hook that is not there, is [HookNotFound] and is not modified.
  Future<List<HookAction>> uninstall() async {
    final actions = <HookAction>[];
    for (final hook in HookName.values) {
      final path = _store.pathOf(hook);
      final existing = await _store.read(hook);
      if (existing == null || !isManagedHook(existing)) {
        actions.add(HookNotFound(hook, path));
        continue;
      }
      await _store.delete(hook);
      actions.add(HookRemoved(hook, path));
      final backup = await _store.restoreLatestBackup(hook);
      if (backup != null) actions.add(HookRestored(hook, path, backup));
    }
    return actions;
  }

  Future<HookAction> _installOne(HookName hook, {required bool force}) async {
    final path = _store.pathOf(hook);
    final existing = await _store.read(hook);
    final script = renderHookScript(hook);
    if (existing == null) {
      await _store.write(hook, script);
      return HookInstalled(hook, path);
    }
    if (isManagedHook(existing)) {
      if (existing == script) return HookUpToDate(hook, path);
      await _store.write(hook, script);
      return HookUpdated(hook, path);
    }
    if (!force) return HookRefused(hook, path);
    final backup = await _store.backup(hook);
    await _store.write(hook, script);
    return HookReplaced(hook, path, backup);
  }

  List<HookName> _inOrder(Set<HookName> hooks) {
    final ordered = hooks.toList()..sort((a, b) => a.index.compareTo(b.index));
    return ordered;
  }
}

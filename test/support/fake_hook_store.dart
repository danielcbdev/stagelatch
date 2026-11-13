import 'package:stagelatch/src/application/hooks/hook_name.dart';
import 'package:stagelatch/src/application/ports/hook_store.dart';

/// An in-memory [HookStore].
///
/// Backups are kept by file name. The unnumbered name is used first;
/// the next one is `<hook>.stagelatch-backup.1`, then `.2`.
final class FakeHookStore implements HookStore {
  /// Creates a store whose hooks live under [directory].
  new({this.directory = '/hooks'});

  /// The directory [pathOf] reports.
  final String directory;

  /// Current hook scripts, keyed by hook.
  final files = <HookName, String>{};

  /// Backup file name to the script it holds.
  final backups = <String, String>{};

  /// What [directoryIsTracked] answers.
  bool tracked = false;

  @override
  String pathOf(HookName hook) => '$directory/${hook.fileName}';

  @override
  Future<String?> read(HookName hook) async => files[hook];

  @override
  Future<void> write(HookName hook, String content) async {
    files[hook] = content;
  }

  @override
  Future<void> delete(HookName hook) async {
    files.remove(hook);
  }

  @override
  Future<String> backup(HookName hook) async {
    final content = files[hook];
    if (content == null) {
      throw StateError('No ${hook.fileName} hook to back up.');
    }
    final name = _nextBackup(hook);
    backups[name] = content;
    return name;
  }

  @override
  Future<String?> restoreLatestBackup(HookName hook) async {
    final name = _newestBackup(hook);
    if (name == null) return null;
    final content = backups[name];
    if (content == null) return null;
    files[hook] = content;
    return name;
  }

  @override
  Future<bool> get directoryIsTracked async => tracked;

  String _nextBackup(HookName hook) {
    final base = '${hook.fileName}.stagelatch-backup';
    if (!backups.containsKey(base)) return base;
    var n = 1;
    while (backups.containsKey('$base.$n')) {
      n += 1;
    }
    return '$base.$n';
  }

  String? _newestBackup(HookName hook) {
    final base = '${hook.fileName}.stagelatch-backup';
    String? numbered;
    var highest = -1;
    for (final name in backups.keys) {
      if (name == base || !name.startsWith('$base.')) continue;
      final n = int.tryParse(name.substring(base.length + 1));
      if (n != null && n > highest) {
        highest = n;
        numbered = name;
      }
    }
    if (numbered != null) return numbered;
    if (backups.containsKey(base)) return base;
    return null;
  }
}

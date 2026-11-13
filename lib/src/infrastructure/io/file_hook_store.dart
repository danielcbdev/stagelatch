/// Hook scripts on the local disk (security rules S3 and S12).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/hooks/hook_name.dart';
import 'package:stagelatch/src/application/ports/hook_store.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';

/// Reads and writes hook files under the directory git reported.
///
/// After resolving symlinks, a path is written only when it lies inside
/// that directory (security rule S3). Bytes are written with
/// [File.writeAsBytes], never through a text mode that could turn LF into
/// CRLF. On platforms that have permission bits the script is marked
/// executable afterwards.
final class FileHookStore implements HookStore {
  /// Creates a store for [hooksDirectory].
  ///
  /// [git], when given, answers [directoryIsTracked]. Without it the
  /// directory is reported as untracked.
  new({required this.hooksDirectory, this.git});

  /// The hooks directory git reported, before symlink resolution.
  final String hooksDirectory;

  /// Used to decide [directoryIsTracked]. Null reports the directory as
  /// untracked.
  final GitProcess? git;

  @override
  String pathOf(HookName hook) => p.join(hooksDirectory, hook.fileName);

  @override
  Future<String?> read(HookName hook) async {
    final directory = Directory(hooksDirectory);
    if (!directory.existsSync()) return null;
    final root = directory.resolveSymbolicLinksSync();
    final destination = p.join(root, hook.fileName);
    final type = FileSystemEntity.typeSync(destination, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type == FileSystemEntityType.link) {
      _requireInside(root, Link(destination).resolveSymbolicLinksSync());
    }
    final bytes = await File(destination).readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<void> write(HookName hook, String content) async {
    final root = await _ensureRoot();
    final destination = p.join(root, hook.fileName);
    await _rejectOutsideLink(root, destination);
    // Binary write: a text write on Windows would expand LF to CRLF and
    // the hook would fail with `\r: command not found`.
    await File(destination).writeAsBytes(utf8.encode(content), flush: true);
    await _makeExecutable(destination);
  }

  @override
  Future<void> delete(HookName hook) async {
    final directory = Directory(hooksDirectory);
    if (!directory.existsSync()) return;
    final root = directory.resolveSymbolicLinksSync();
    final destination = p.join(root, hook.fileName);
    final type = FileSystemEntity.typeSync(destination, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.link) {
      _requireInside(root, Link(destination).resolveSymbolicLinksSync());
      // Delete the link itself. File.delete would follow it and remove
      // whatever it points at.
      await Link(destination).delete();
      return;
    }
    _requireInside(root, File(destination).resolveSymbolicLinksSync());
    await File(destination).delete();
  }

  @override
  Future<String> backup(HookName hook) async {
    final current = await read(hook);
    if (current == null) {
      throw UsageException('No ${hook.fileName} hook to back up.');
    }
    final root = await _ensureRoot();
    final name = _nextBackupName(root, hook);
    final destination = p.join(root, name);
    _requireInside(root, destination);
    await File(destination).writeAsBytes(utf8.encode(current), flush: true);
    return destination;
  }

  @override
  Future<String?> restoreLatestBackup(HookName hook) async {
    final directory = Directory(hooksDirectory);
    if (!directory.existsSync()) return null;
    final root = directory.resolveSymbolicLinksSync();
    final newest = _newestBackup(root, hook);
    if (newest == null) return null;
    final bytes = await File(p.join(root, newest)).readAsBytes();
    await write(hook, utf8.decode(bytes, allowMalformed: true));
    return p.join(root, newest);
  }

  @override
  Future<bool> get directoryIsTracked async {
    final git = this.git;
    if (git == null) return false;
    final relative = p.relative(hooksDirectory, from: git.workingDirectory);
    if (p.isAbsolute(relative) || relative.startsWith('..')) return false;
    // git arguments use forward slashes even on Windows.
    final gitPath = relative.replaceAll('\\', '/');
    // -z: NUL-separated names. An empty result means no tracked file lives
    // under the hooks directory.
    final result = await git.run(['ls-files', '-z', '--', gitPath]);
    return result.stdout.isNotEmpty;
  }

  Future<String> _ensureRoot() async {
    final directory = Directory(hooksDirectory);
    if (!directory.existsSync()) await directory.create(recursive: true);
    return directory.resolveSymbolicLinksSync();
  }

  /// A symlink is followed by [File.writeAsBytes]. If it points outside
  /// the hooks directory, writing it would modify that outside file.
  Future<void> _rejectOutsideLink(String root, String destination) async {
    final type = FileSystemEntity.typeSync(destination, followLinks: false);
    if (type != FileSystemEntityType.link) return;
    _requireInside(root, Link(destination).resolveSymbolicLinksSync());
    await Link(destination).delete();
  }

  void _requireInside(String root, String candidate) {
    final target = p.canonicalize(candidate);
    final normalizedRoot = p.canonicalize(root);
    final inside =
        target == normalizedRoot || p.isWithin(normalizedRoot, target);
    if (inside) return;
    throw UsageException(
      'Refusing to touch $candidate: it resolves outside the hooks '
      'directory $root.',
    );
  }

  String _nextBackupName(String root, HookName hook) {
    final base = '${hook.fileName}.stagelatch-backup';
    if (!File(p.join(root, base)).existsSync()) return base;
    var n = 1;
    while (File(p.join(root, '$base.$n')).existsSync()) {
      n += 1;
    }
    return '$base.$n';
  }

  String? _newestBackup(String root, HookName hook) {
    final base = '${hook.fileName}.stagelatch-backup';
    // The suffix is digits only, so the match cannot backtrack (S6).
    final numbered = RegExp('^${RegExp.escape(base)}\\.(\\d+)\$');
    String? best;
    var highest = -1;
    for (final entity in Directory(root).listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      final match = numbered.firstMatch(name);
      if (match == null) continue;
      final n = int.parse(match.group(1) ?? '');
      if (n > highest) {
        highest = n;
        best = name;
      }
    }
    if (best != null) return best;
    if (File(p.join(root, base)).existsSync()) return base;
    return null;
  }

  Future<void> _makeExecutable(String path) async {
    if (Platform.isWindows) return;
    // Fixed argument list. [path] was checked to lie inside the hooks
    // directory (security rules S1 and S3).
    final result = await Process.run('chmod', ['755', path]);
    if (result.exitCode != 0) {
      throw InternalException(
        'Could not mark the hook executable: ${result.stderr}',
        where: path,
      );
    }
  }
}

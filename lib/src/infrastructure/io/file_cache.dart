/// The cache of the facts, on disk (docs/specs/dart-toolchain.md,
/// section 6.1; security S3).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/ports/cache.dart';

/// Renames [from] to [to]; replaceable so a test can make it fail.
typedef RenameFile = Future<void> Function(String from, String to);

/// A [Cache] in
/// `<git common dir>/stagelatch/cache/<namespace>/<two characters>/<key>`,
/// where the two characters are the first two of the key.
///
/// Linked worktrees share the common directory, so they share the cache.
/// Every I/O failure is a miss on read and an abandoned write: the cache
/// never changes a verdict. The directory is safe to delete at any time.
///
/// S3: the cache directory is used only when, with symbolic links
/// resolved, it lies inside the common directory. `stagelatch/` and
/// `stagelatch/cache/` come from the repository's own `.git`, so a link
/// there must not send a write elsewhere. Nothing is created by the
/// constructor or by [read].
final class FileCache implements Cache {
  /// Creates a cache under the git common directory. [rename] defaults to
  /// `File.rename`.
  new({required this._commonDir, RenameFile? rename})
    : _rename = rename ?? _renameFile;

  static Future<void> _renameFile(String from, String to) async {
    await File(from).rename(to);
  }

  static final RegExp _namespacePattern = RegExp(r'^[a-z0-9-]+$');
  static final RegExp _keyPattern = RegExp(r'^[0-9a-f-]{2,}$');

  final String _commonDir;
  final RenameFile _rename;

  /// The verified cache directory, once it has been. Only a success is
  /// kept: a failure may be gone the next time.
  String? _root;

  @override
  Future<String?> read(String namespace, String key) async {
    _validate(namespace, key);
    try {
      final root = await _verifiedRoot(create: false);
      if (root == null) return null;
      return await File(_entryPath(root, namespace, key)).readAsString();
    } on IOException {
      return null;
    } on FormatException {
      // Not valid UTF-8: a damaged entry is a miss.
      return null;
    }
  }

  @override
  Future<void> write(String namespace, String key, String value) async {
    _validate(namespace, key);
    try {
      final root = await _verifiedRoot(create: true);
      if (root == null) return;
      final target = _entryPath(root, namespace, key);
      final shard = Directory(p.dirname(target));
      await shard.create(recursive: true);
      // A fresh directory next to the target: nobody else writes into it,
      // and the rename below is within one directory, so it is atomic.
      final scratch = await shard.createTemp('tmp-');
      try {
        final staged = p.join(scratch.path, 'value');
        await File(staged).writeAsString(value, flush: true);
        try {
          await _rename(staged, target);
        } on FileSystemException {
          // The entry exists already (Windows does not rename over a file)
          // or the write is abandoned. Writers of one key store the same
          // bytes, so either is fine.
        }
      } finally {
        await _deleteQuietly(scratch);
      }
    } on IOException {
      // Unwritable: every write is a no-op.
    }
  }

  static void _validate(String namespace, String key) {
    if (!_namespacePattern.hasMatch(namespace)) {
      throw ArgumentError.value(
        namespace,
        'namespace',
        'must match [a-z0-9-]+',
      );
    }
    if (!_keyPattern.hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'must match [0-9a-f-]{2,}');
    }
  }

  static String _entryPath(String root, String namespace, String key) =>
      p.join(root, namespace, key.substring(0, 2), key);

  static Future<void> _deleteQuietly(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } on IOException {
      // Left behind at worst; the cache is safe to delete at any time.
    }
  }

  /// `<commonDir>/stagelatch/cache`, when it lies inside the common
  /// directory once links are resolved; otherwise null.
  ///
  /// With [create], missing directories are made, one level at a time and
  /// each checked first, so a link is never followed out before it is
  /// noticed.
  Future<String?> _verifiedRoot({required bool create}) async {
    final known = _root;
    if (known != null) return known;
    final String common;
    try {
      common = await Directory(_commonDir).resolveSymbolicLinks();
    } on FileSystemException {
      return null;
    }
    final stagelatch = p.join(_commonDir, 'stagelatch');
    final cache = p.join(stagelatch, 'cache');
    for (final path in [stagelatch, cache]) {
      final exists =
          FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound;
      if (!exists) {
        if (!create) return null;
        await Directory(path).create();
      }
      if (!await _isInside(path, common)) return null;
    }
    if (FileSystemEntity.typeSync(cache) != FileSystemEntityType.directory) {
      return null;
    }
    return _root = cache;
  }

  /// Whether [path], with every link resolved, is [common] or below it.
  static Future<bool> _isInside(String path, String common) async {
    try {
      final resolved = await Directory(path).resolveSymbolicLinks();
      return p.isWithin(common, resolved);
    } on FileSystemException {
      return false;
    }
  }
}

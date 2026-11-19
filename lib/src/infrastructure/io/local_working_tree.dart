/// The working tree on the local disk.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/working_tree.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// Reads and writes files under [root], which is the repository root.
///
/// A path that resolves outside [root] is refused (security rule S3).
/// Bytes are written as given, so a config file keeps the LF it was
/// rendered with.
final class LocalWorkingTree implements WorkingTree {
  /// Creates a tree rooted at [root].
  new(this.root);

  /// The repository root, absolute.
  final String root;

  @override
  Future<String?> readText(RepoPath path) async {
    final file = _file(path);
    if (!file.existsSync()) return null;
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  @override
  Future<void> writeText(RepoPath path, String content) async {
    final file = _file(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(utf8.encode(content), flush: true);
  }

  @override
  Future<bool> exists(RepoPath path) async => _file(path).existsSync();

  File _file(RepoPath path) {
    final target = p.normalize(p.join(root, path.value));
    final normalized = p.normalize(root);
    final inside = target == normalized || p.isWithin(normalized, target);
    if (!inside) {
      throw UsageException(
        'Refusing to touch $target: it is outside the repository $root.',
      );
    }
    return File(target);
  }
}

/// The snapshot written to a temporary directory for the SDK to read
/// (ADR-0001, docs/specs/dart-toolchain.md, section 4).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// A directory that holds the snapshot's Dart and YAML files, byte for
/// byte, and each package's `.dart_tool/package_config.json`.
///
/// The SDK analyzes this directory, never the working tree, so an unstaged
/// edit, an untracked file and a file deleted only in the index are all
/// invisible to the verdict.
final class MaterializedSnapshot {
  const new _(this.root, this._repoRoot);

  /// Writes the snapshot into a new directory from
  /// `Directory.systemTemp.createTemp` (security S10).
  ///
  /// With [settingsOnly], only `pubspec.yaml` and `analysis_options.yaml`
  /// files are written: enough for `dart format` to find its settings.
  static Future<MaterializedSnapshot> write({
    required SnapshotFiles snapshot,
    required String repoRoot,
    required Iterable<DartPackage> packages,
    bool settingsOnly = false,
  }) async {
    final created = await Directory.systemTemp.createTemp('stagelatch-');
    // Resolved, because the server reports real paths (on macOS the temp
    // directory is behind a symlink).
    final materialized = MaterializedSnapshot._(
      await created.resolveSymbolicLinks(),
      repoRoot,
    );
    for (final entry in await snapshot.list()) {
      if (!entry.mode.isFile || !_wanted(entry.path, settingsOnly)) continue;
      final bytes = await snapshot.readBytes(entry.path);
      if (bytes == null) continue;
      final file = File(materialized.pathOf(entry.path));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
    for (final package in packages) {
      await materialized._copyPackageConfig(package.root);
    }
    return materialized;
  }

  /// The directory's absolute, real path.
  final String root;

  final String _repoRoot;

  static bool _wanted(RepoPath path, bool settingsOnly) {
    if (settingsOnly) {
      return path.basename == 'pubspec.yaml' ||
          path.basename == 'analysis_options.yaml';
    }
    return const {'.dart', '.yaml', '.yml'}.contains(path.extension);
  }

  /// Where [path] is inside this directory.
  String pathOf(RepoPath path) => p.joinAll([root, ...path.value.split('/')]);

  /// The repository path of [absolutePath], or null when it is outside.
  RepoPath? repoPathOf(String absolutePath) {
    if (!p.isWithin(root, absolutePath)) return null;
    return RepoPath(p.split(p.relative(absolutePath, from: root)).join('/'));
  }

  /// Copies the working tree's package config of the package at
  /// [packageRoot], when there is one, with every `rootUri` that leaves the
  /// repository made absolute. Relative URIs inside the repository stay
  /// relative, so they point into this directory, as the spike's oracle
  /// does.
  Future<void> _copyPackageConfig(RepoPath? packageRoot) async {
    final segments = [...?packageRoot?.value.split('/')];
    final source = File(
      p.joinAll([_repoRoot, ...segments, '.dart_tool', 'package_config.json']),
    );
    if (!source.existsSync()) return;
    final Object? json;
    try {
      json = jsonDecode(await source.readAsString());
    } on FormatException {
      return;
    }
    final base = Uri.directory(p.dirname(source.path));
    if (json case {'packages': final List<Object?> entries}) {
      for (final entry in entries) {
        if (entry is! Map<String, Object?>) continue;
        final rootUri = entry['rootUri'];
        if (rootUri is! String) continue;
        final target = base.resolve(rootUri);
        if (target.scheme != 'file') continue;
        final absolute = target.toFilePath();
        final inside =
            p.equals(_repoRoot, absolute) || p.isWithin(_repoRoot, absolute);
        if (!inside) {
          entry['rootUri'] = Uri.directory(absolute).toString();
        } else if (Uri.parse(rootUri).isAbsolute) {
          entry['rootUri'] = Uri.directory(
            p.join(root, p.relative(absolute, from: _repoRoot)),
          ).toString();
        }
      }
    }
    final target = File(
      p.joinAll([root, ...segments, '.dart_tool', 'package_config.json']),
    );
    await target.parent.create(recursive: true);
    await target.writeAsString(jsonEncode(json));
  }

  /// Removes the directory.
  Future<void> delete() async {
    final directory = Directory(root);
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}

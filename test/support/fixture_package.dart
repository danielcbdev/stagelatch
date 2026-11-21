/// A copy of `test/fixtures/dart_app` that tests may change freely.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies the fixture package into a new temporary directory, runs the SDK's
/// `dart pub get --offline` there and returns the directory, symlinks
/// resolved.
///
/// The package has no dependencies, so no network is needed. With
/// [withTestPackage] the copy (not the fixture) gets `dev_dependencies:
/// test`, with the constraint of this repository, which `dart pub get` of
/// the repository has already put in the pub cache.
///
/// The caller deletes it.
Future<String> copyFixturePackage({bool withTestPackage = false}) async {
  final created = await Directory.systemTemp.createTemp('stagelatch_app_');
  final root = await created.resolveSymbolicLinks();
  final source = Directory(p.join('test', 'fixtures', 'dart_app'));
  await for (final entity in source.list(recursive: true)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: source.path);
    if (p.split(relative).contains('.dart_tool')) continue;
    final target = File(p.join(root, relative));
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
  if (withTestPackage) {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    await pubspec.writeAsString(
      '${await pubspec.readAsString()}\n'
      'dev_dependencies:\n'
      '  test: ^1.33.0\n',
    );
  }
  await pubGetOffline(root);
  return root;
}

/// Runs the SDK's `dart pub get --offline` in [root], which must be a
/// package whose dependencies are all in the pub cache.
///
/// Throws [StateError] with the tool's message when it fails.
Future<void> pubGetOffline(String root) async {
  final result = await Process.run(
    'dart',
    ['--suppress-analytics', 'pub', 'get', '--offline'],
    workingDirectory: root,
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    throw StateError('dart pub get failed: ${result.stderr}');
  }
}

/// Writes [content] to [path] under [root], creating directories.
Future<void> writeFile(String root, String path, String content) async {
  final file = File(p.join(root, path));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

/// Copies `test/fixtures/workspace` into a new temporary directory, runs
/// `dart pub get --offline` at the workspace root and returns the
/// directory, symlinks resolved.
///
/// Members have no local `.dart_tool` or lock after pub get; the root
/// holds both. The caller deletes the directory.
Future<String> copyWorkspaceFixture() async {
  final created = await Directory.systemTemp.createTemp('stagelatch_ws_');
  final root = await created.resolveSymbolicLinks();
  final source = Directory(p.join('test', 'fixtures', 'workspace'));
  await for (final entity in source.list(recursive: true)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: source.path);
    if (p.split(relative).contains('.dart_tool')) continue;
    final target = File(p.join(root, relative));
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
  await pubGetOffline(root);
  return root;
}

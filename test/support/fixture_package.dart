/// A copy of `test/fixtures/dart_app` that tests may change freely.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies the fixture package into a new temporary directory, runs the SDK's
/// `dart pub get --offline` there (the package has no dependencies, so no
/// network is needed) and returns the directory, symlinks resolved.
///
/// The caller deletes it.
Future<String> copyFixturePackage() async {
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
  final result = await Process.run(
    'dart',
    ['--suppress-analytics', 'pub', 'get', '--offline'],
    workingDirectory: root,
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    throw StateError('dart pub get failed: ${result.stderr}');
  }
  return root;
}

/// Writes [content] to [path] under [root], creating directories.
Future<void> writeFile(String root, String path, String content) async {
  final file = File(p.join(root, path));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

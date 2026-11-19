import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:stagelatch/src/infrastructure/dart/materialized_snapshot.dart';
import 'package:test/test.dart';

import '../../support/fake_snapshot_files.dart';

void main() {
  late String repo;

  setUp(() async {
    final created = await Directory.systemTemp.createTemp('materialize_');
    repo = await created.resolveSymbolicLinks();
  });

  tearDown(() => Directory(repo).delete(recursive: true));

  Future<MaterializedSnapshot> write(
    FakeSnapshotFiles snapshot, {
    List<DartPackage> packages = const [],
    bool settingsOnly = false,
  }) async {
    final materialized = await MaterializedSnapshot.write(
      snapshot: snapshot,
      repoRoot: repo,
      packages: packages,
      settingsOnly: settingsOnly,
    );
    addTearDown(materialized.delete);
    return materialized;
  }

  List<String> filesUnder(String root) => [
    for (final entity in Directory(root).listSync(recursive: true))
      if (entity is File)
        p.split(p.relative(entity.path, from: root)).join('/'),
  ]..sort();

  test('writes regular and executable .dart, .yaml and .yml files byte for '
      'byte, and nothing else', () async {
    final materialized = await write(
      FakeSnapshotFiles(
        {
          'lib/a.dart': 'a\r\n',
          'bin/run.dart': 'run',
          'pubspec.yaml': 'name: x\n',
          'l10n.yml': 'arb-dir: lib\n',
          'assets/logo.png': [137, 80, 78, 71],
          'lib/link.dart': 'a.dart',
          'vendor/sub': '',
        },
        modes: {
          'bin/run.dart': FileMode.executable,
          'lib/link.dart': FileMode.symlink,
          'vendor/sub': FileMode.gitlink,
        },
      ),
    );

    expect(filesUnder(materialized.root), [
      'bin/run.dart',
      'l10n.yml',
      'lib/a.dart',
      'pubspec.yaml',
    ]);
    expect(
      File(materialized.pathOf(RepoPath('lib/a.dart'))).readAsStringSync(),
      'a\r\n',
    );
  });

  test(
    'settingsOnly writes only pubspec.yaml and analysis_options.yaml',
    () async {
      final materialized = await write(
        FakeSnapshotFiles({
          'lib/a.dart': 'a',
          'pubspec.yaml': 'name: x\n',
          'analysis_options.yaml': '',
          'l10n.yaml': '',
        }),
        settingsOnly: true,
      );

      expect(filesUnder(materialized.root), [
        'analysis_options.yaml',
        'pubspec.yaml',
      ]);
    },
  );

  test('package config roots inside the repository stay relative; others '
      'become absolute', () async {
    final outside = await Directory.systemTemp.createTemp('pub_cache_');
    addTearDown(() => outside.delete(recursive: true));
    File(p.join(repo, 'app', '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'app', 'rootUri': '../', 'packageUri': 'lib/'},
            {
              'name': 'ui',
              'rootUri': '../../packages/ui',
              'packageUri': 'lib/',
            },
            {
              'name': 'design',
              'rootUri': '../../../design',
              'packageUri': 'lib/',
            },
            {
              'name': 'http',
              'rootUri': Uri.directory(outside.path).toString(),
              'packageUri': 'lib/',
            },
          ],
        }),
      );

    final materialized = await write(
      FakeSnapshotFiles({'app/pubspec.yaml': 'name: app\n'}),
      packages: [DartPackage(root: RepoPath('app'), name: 'app')],
    );

    final copied = jsonDecode(
      File(
        p.join(materialized.root, 'app', '.dart_tool', 'package_config.json'),
      ).readAsStringSync(),
    ) as Map<String, Object?>;
    final roots = [
      for (final entry in copied['packages']! as List<Object?>)
        (entry! as Map<String, Object?>)['rootUri'],
    ];
    expect(roots, [
      '../',
      '../../packages/ui',
      Uri.directory(p.normalize(p.join(repo, '..', 'design'))).toString(),
      Uri.directory(outside.path).toString(),
    ]);
  });

  test('paths with spaces and non-ASCII characters round-trip through '
      'pathOf and repoPathOf', () async {
    final path = RepoPath('dir with space/café.dart');
    final materialized = await write(FakeSnapshotFiles({path.value: 'x'}));

    final absolute = materialized.pathOf(path);

    expect(File(absolute).existsSync(), isTrue);
    expect(materialized.repoPathOf(absolute), path);
    expect(materialized.repoPathOf(p.join(repo, 'other.dart')), isNull);
  });

  test('delete removes the directory', () async {
    final materialized = await MaterializedSnapshot.write(
      snapshot: FakeSnapshotFiles({'a.dart': 'a'}),
      repoRoot: repo,
      packages: const [],
    );

    await materialized.delete();

    expect(Directory(materialized.root).existsSync(), isFalse);
  });
}

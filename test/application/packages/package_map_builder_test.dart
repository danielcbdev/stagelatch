import 'package:stagelatch/src/application/packages/package_map_builder.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_snapshot_files.dart';

Future<PackageMap> _build(
  Map<String, Object> files, {
  Map<String, FileMode> modes = const {},
}) => buildPackageMap(
  FakeSnapshotFiles(files, modes: modes),
  const StructuredDocuments(),
);

void main() {
  test('a file belongs to the nearest enclosing pubspec', () async {
    final map = await _build({
      'pubspec.yaml': 'name: app\n',
      'packages/ui/pubspec.yaml': 'name: ui\n',
      'packages/ui/lib/a.dart': '',
      'lib/b.dart': '',
    });

    expect(map.packageOf(RepoPath('packages/ui/lib/a.dart'))!.name, 'ui');
    expect(map.packageOf(RepoPath('lib/b.dart'))!.name, 'app');
  });

  test('a file outside every package has none', () async {
    final map = await _build({
      'tools/pubspec.yaml': 'name: tools\n',
      'lib/b.dart': '',
    });

    expect(map.packageOf(RepoPath('lib/b.dart')), isNull);
  });

  test('usesFlutter is read from an sdk: flutter dependency', () async {
    final map = await _build({
      'app/pubspec.yaml':
          'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      'tests_only/pubspec.yaml':
          'name: t\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n',
      'pure/pubspec.yaml': 'name: pure\ndependencies:\n  path: ^1.9.0\n',
    });

    expect(
      [for (final package in map.packages) (package.name, package.usesFlutter)],
      [('app', true), ('pure', false), ('t', true)],
    );
  });

  test('an unparseable pubspec, or one without a string name, still defines '
      'a package with an empty name', () async {
    final map = await _build({
      'tool/pubspec.yaml': 'name: [unclosed\n',
      'other/pubspec.yaml': 'name: 3\n',
    });

    expect(
      map.packageOf(RepoPath('tool/x.dart')),
      DartPackage(root: RepoPath('tool'), name: ''),
    );
    expect(map.packageOf(RepoPath('other/x.dart'))!.name, '');
  });

  test('packages are sorted by root', () async {
    final map = await _build({
      'z/pubspec.yaml': 'name: z\n',
      'pubspec.yaml': 'name: root\n',
      'a/pubspec.yaml': 'name: a\n',
    });

    expect(map.packages.map((package) => package.root?.value), [
      null,
      'a',
      'z',
    ]);
  });

  test('a pubspec.yaml that is a symlink or a submodule entry defines no '
      'package', () async {
    final map = await _build(
      {'linked/pubspec.yaml': '../x', 'sub/pubspec.yaml': ''},
      modes: {
        'linked/pubspec.yaml': FileMode.symlink,
        'sub/pubspec.yaml': FileMode.gitlink,
      },
    );

    expect(map.packages, isEmpty);
  });
}

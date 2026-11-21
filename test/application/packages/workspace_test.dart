import 'package:stagelatch/src/application/packages/package_map_builder.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_snapshot_files.dart';

Future<PackageMap> _build(Map<String, Object> files) =>
    buildPackageMap(FakeSnapshotFiles(files), const StructuredDocuments());

void main() {
  test('a member with resolution: workspace resolves to the root that lists '
      'it', () async {
    final map = await _build({
      'pubspec.yaml':
          'name: root\nenvironment:\n  sdk: ^3.13.0\n'
          'workspace:\n  - packages/a\n',
      'packages/a/pubspec.yaml':
          'name: a\nenvironment:\n  sdk: ^3.13.0\n'
          'resolution: workspace\n',
    });

    final a = map.packageOf(RepoPath('packages/a/lib/x.dart'))!;
    final root = map.packageOf(RepoPath('pubspec.yaml'))!;

    expect(map.resolutionPackageOf(a), root);
    expect(map.resolutionRootOf(a), isNull);
    expect(map.resolutionRootOf(root), isNull);
  });

  test('workspace globs of the root pubspec are matched against the packages '
      'of the snapshot', () async {
    final map = await _build({
      'pubspec.yaml':
          'name: root\nenvironment:\n  sdk: ^3.11.0\n'
          'workspace:\n  - packages/*\n',
      'packages/a/pubspec.yaml':
          'name: a\nenvironment:\n  sdk: ^3.11.0\n'
          'resolution: workspace\n',
      'packages/b/pubspec.yaml':
          'name: b\nenvironment:\n  sdk: ^3.11.0\n'
          'resolution: workspace\n',
      'other/c/pubspec.yaml':
          'name: c\nenvironment:\n  sdk: ^3.11.0\n'
          'resolution: workspace\n',
    });

    final a = map.packages.firstWhere((p) => p.name == 'a');
    final b = map.packages.firstWhere((p) => p.name == 'b');
    final c = map.packages.firstWhere((p) => p.name == 'c');
    final root = map.packages.firstWhere((p) => p.name == 'root');

    expect(map.resolutionPackageOf(a), root);
    expect(map.resolutionPackageOf(b), root);
    expect(map.resolutionPackageOf(c), c);
  });

  test('a package that declares resolution: workspace and is listed by nobody '
      'resolves on its own', () async {
    final map = await _build({
      'pubspec.yaml': 'name: root\nenvironment:\n  sdk: ^3.13.0\n',
      'orphan/pubspec.yaml':
          'name: orphan\nenvironment:\n  sdk: ^3.13.0\n'
          'resolution: workspace\n',
    });

    final orphan = map.packages.firstWhere((p) => p.name == 'orphan');

    expect(map.resolutionPackageOf(orphan), orphan);
    expect(map.resolutionRootOf(orphan), RepoPath('orphan'));
  });

  test('a package without resolution: workspace is unaffected', () async {
    final map = await _build({
      'pubspec.yaml':
          'name: root\nenvironment:\n  sdk: ^3.13.0\n'
          'workspace:\n  - packages/a\n',
      'packages/a/pubspec.yaml': 'name: a\nenvironment:\n  sdk: ^3.13.0\n',
    });

    final a = map.packages.firstWhere((p) => p.name == 'a');

    expect(map.resolutionPackageOf(a), a);
    expect(map.resolutionRootOf(a), RepoPath('packages/a'));
  });

  test('two workspaces in one repository keep their members apart', () async {
    final map = await _build({
      'one/pubspec.yaml':
          'name: one\nenvironment:\n  sdk: ^3.13.0\n'
          'workspace:\n  - packages/a\n',
      'one/packages/a/pubspec.yaml':
          'name: a\nenvironment:\n  sdk: ^3.13.0\n'
          'resolution: workspace\n',
      'two/pubspec.yaml':
          'name: two\nenvironment:\n  sdk: ^3.13.0\n'
          'workspace:\n  - packages/a\n',
      'two/packages/a/pubspec.yaml':
          'name: a2\nenvironment:\n  sdk: ^3.13.0\n'
          'resolution: workspace\n',
    });

    final one = map.packages.firstWhere((p) => p.name == 'one');
    final two = map.packages.firstWhere((p) => p.name == 'two');
    final a = map.packages.firstWhere((p) => p.name == 'a');
    final a2 = map.packages.firstWhere((p) => p.name == 'a2');

    expect(map.resolutionPackageOf(a), one);
    expect(map.resolutionPackageOf(a2), two);
    expect(map.resolutionRootOf(a), RepoPath('one'));
    expect(map.resolutionRootOf(a2), RepoPath('two'));
  });

  test('workspaceMembersOf lists every package of the root, the root included, '
      'and just the package outside a workspace', () async {
    final map = await _build({
      'pubspec.yaml':
          'name: root\nenvironment:\n  sdk: ^3.13.0\n'
          'workspace:\n  - packages/a\n  - packages/b\n',
      'packages/a/pubspec.yaml':
          'name: a\nenvironment:\n  sdk: ^3.13.0\n'
          'resolution: workspace\n',
      'packages/b/pubspec.yaml':
          'name: b\nenvironment:\n  sdk: ^3.13.0\n'
          'resolution: workspace\n',
      'solo/pubspec.yaml': 'name: solo\nenvironment:\n  sdk: ^3.13.0\n',
    });

    final root = map.packages.firstWhere((p) => p.name == 'root');
    final a = map.packages.firstWhere((p) => p.name == 'a');
    final solo = map.packages.firstWhere((p) => p.name == 'solo');

    expect(map.workspaceMembersOf(a).map((p) => p.name), ['root', 'a', 'b']);
    expect(map.workspaceMembersOf(root).map((p) => p.name), ['root', 'a', 'b']);
    expect(map.workspaceMembersOf(solo), [solo]);
  });

  test(
    'a nested workspace root wins over an outer one for the same member',
    () async {
      final map = await _build({
        'pubspec.yaml':
            'name: outer\nenvironment:\n  sdk: ^3.13.0\n'
            'workspace:\n  - nested/packages/a\n',
        'nested/pubspec.yaml':
            'name: inner\nenvironment:\n  sdk: ^3.13.0\n'
            'workspace:\n  - packages/a\n',
        'nested/packages/a/pubspec.yaml':
            'name: a\nenvironment:\n  sdk: ^3.13.0\n'
            'resolution: workspace\n',
      });

      final a = map.packages.firstWhere((p) => p.name == 'a');
      final inner = map.packages.firstWhere((p) => p.name == 'inner');

      expect(map.resolutionPackageOf(a), inner);
    },
  );
}

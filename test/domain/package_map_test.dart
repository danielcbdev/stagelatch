import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:test/test.dart';

void main() {
  const app = DartPackage(root: null, name: 'app', usesFlutter: true);
  final ui = DartPackage(root: RepoPath('packages/ui'), name: 'ui');
  final nested = DartPackage(
    root: RepoPath('packages/ui/example'),
    name: 'ui_example',
  );

  group('PackageMap.packageOf', () {
    final map = PackageMap([nested, app, ui]);

    test(
      'returns the package with the deepest root that contains the file',
      () {
        expect(map.packageOf(RepoPath('packages/ui/lib/a.dart')), ui);
        expect(
          map.packageOf(RepoPath('packages/ui/example/lib/main.dart')),
          nested,
        );
      },
    );

    test('falls back to the package at the repository root', () {
      expect(map.packageOf(RepoPath('lib/main.dart')), app);
      expect(map.packageOf(RepoPath('pubspec.yaml')), app);
      expect(map.packageOf(RepoPath('packages/other/a.dart')), app);
    });

    test('assigns a pubspec to the package it defines', () {
      expect(map.packageOf(RepoPath('packages/ui/pubspec.yaml')), ui);
    });

    test('does not match a directory that only shares a name prefix', () {
      expect(map.packageOf(RepoPath('packages/ui_kit/lib/a.dart')), app);
    });

    test('returns null when no package contains the file', () {
      final withoutRoot = PackageMap([ui]);

      expect(withoutRoot.packageOf(RepoPath('lib/main.dart')), isNull);
      expect(withoutRoot.packageOf(RepoPath('README.md')), isNull);
    });
  });

  group('PackageMap', () {
    test('lists packages sorted by root, the repository root first', () {
      final map = PackageMap([nested, ui, app]);

      expect(map.packages.map((package) => package.name), [
        'app',
        'ui',
        'ui_example',
      ]);
    });

    test('rejects two packages with the same root', () {
      expect(
        () => PackageMap([
          ui,
          DartPackage(root: RepoPath('packages/ui'), name: 'other'),
        ]),
        throwsArgumentError,
      );
    });

    test('can be empty', () {
      expect(PackageMap(const []).packages, isEmpty);
      expect(PackageMap(const []).packageOf(RepoPath('a.dart')), isNull);
    });
  });

  group('DartPackage', () {
    test('is equal when root, name and usesFlutter are equal', () {
      expect(ui, DartPackage(root: RepoPath('packages/ui'), name: 'ui'));
      expect(
        ui.hashCode,
        DartPackage(root: RepoPath('packages/ui'), name: 'ui').hashCode,
      );
      expect(ui, isNot(nested));
      expect(app, isNot(const DartPackage(root: null, name: 'app')));
    });

    test('does not use Flutter unless stated', () {
      expect(ui.usesFlutter, isFalse);
    });
  });
}

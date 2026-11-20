import 'package:stagelatch/src/checks/analyze/analysis_scope.dart';
import 'package:stagelatch/src/checks/analyze/analyze_settings.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/dart/import_graph.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_snapshot_files.dart';

final PackageMap _packages = PackageMap([
  const DartPackage(root: null, name: 'app'),
  DartPackage(root: RepoPath('packages/ui'), name: 'ui'),
]);

const Map<String, Object> _files = {
  'pubspec.yaml': 'name: app\n',
  'lib/a.dart': '',
  'lib/b.dart': '',
  'lib/uses_a.dart': '',
  'lib/uses_uses_a.dart': '',
  'lib/uses_gone.dart': '',
  'packages/ui/pubspec.yaml': 'name: ui\n',
  'packages/ui/lib/button.dart': '',
  'packages/ui/lib/other.dart': '',
  'README.md': '',
};

ImportGraph _graph() => ImportGraph.build(
  directives: {
    for (final (from, to) in const [
      ('lib/uses_a.dart', 'a.dart'),
      ('lib/uses_uses_a.dart', 'uses_a.dart'),
      ('lib/uses_gone.dart', 'gone.dart'),
    ])
      RepoPath(from): [
        Directive(
          kind: DirectiveKind.import,
          uri: to,
          location: Location.wholeFile(RepoPath(from)),
        ),
      ],
  },
  packages: _packages,
);

Future<List<String>> _scope(
  AnalyzeScope scope,
  List<FileChange> changes,
) async {
  final context = FakeCheckContext(
    snapshot: FakeSnapshotFiles(_files),
    changes: ChangeSet(changes),
    packages: _packages,
    importGraph: _graph(),
  );
  return [for (final path in await analysisScope(context, scope)) path.value];
}

FileChange _modified(String path) =>
    FileChange(path: RepoPath(path), kind: ChangeKind.modified);

void main() {
  test('scope changed is the changed Dart files', () async {
    expect(
      await _scope(AnalyzeScope.changed, [
        _modified('lib/a.dart'),
        _modified('README.md'),
      ]),
      ['lib/a.dart'],
    );
  });

  test(
    'scope affected adds transitive importers from the same repository',
    () async {
      expect(await _scope(AnalyzeScope.affected, [_modified('lib/a.dart')]), [
        'lib/a.dart',
        'lib/uses_a.dart',
        'lib/uses_uses_a.dart',
      ]);
    },
  );

  test('scope all is every Dart file of each touched package', () async {
    expect(
      await _scope(AnalyzeScope.all, [
        _modified('packages/ui/lib/button.dart'),
      ]),
      ['packages/ui/lib/button.dart', 'packages/ui/lib/other.dart'],
    );
  });

  test('a changed pubspec.yaml or analysis_options.yaml widens that package '
      'to all', () async {
    expect(
      await _scope(AnalyzeScope.changed, [
        _modified('packages/ui/pubspec.yaml'),
      ]),
      ['packages/ui/lib/button.dart', 'packages/ui/lib/other.dart'],
    );
    expect(
      await _scope(AnalyzeScope.affected, [
        FileChange(
          path: RepoPath('analysis_options.yaml'),
          kind: ChangeKind.added,
        ),
      ]),
      [
        'lib/a.dart',
        'lib/b.dart',
        'lib/uses_a.dart',
        'lib/uses_gone.dart',
        'lib/uses_uses_a.dart',
      ],
    );
  });

  test('deleted files are not requested, but their importers are', () async {
    expect(
      await _scope(AnalyzeScope.affected, [
        FileChange(path: RepoPath('lib/gone.dart'), kind: ChangeKind.deleted),
      ]),
      ['lib/uses_gone.dart'],
    );
  });

  test('the old path of a rename counts as deleted', () async {
    expect(
      await _scope(AnalyzeScope.affected, [
        FileChange(
          path: RepoPath('lib/b.dart'),
          kind: ChangeKind.renamed,
          previousPath: RepoPath('lib/gone.dart'),
        ),
      ]),
      ['lib/b.dart', 'lib/uses_gone.dart'],
    );
  });
}

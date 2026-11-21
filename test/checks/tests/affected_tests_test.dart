import 'package:stagelatch/src/checks/tests/affected_tests.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/dart/import_graph.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:test/test.dart';

const _app = DartPackage(root: null, name: 'app');
final _ui = DartPackage(root: RepoPath('packages/ui'), name: 'ui');
final _core = DartPackage(root: RepoPath('packages/core'), name: 'core');

/// The selection for [files] (path to the URIs it names; a `part ` prefix
/// makes a `part`, `part of ` a `part of`, `export ` an `export`) given
/// [changes] written as `M path`, `A path`, `D path` or `R old -> new`.
///
/// [snapshot] defaults to every key of [files]; [extraSnapshot] adds paths
/// that have no directives, such as `pubspec.yaml`.
AffectedTests select(
  Map<String, List<String>> files,
  List<String> changes, {
  List<DartPackage> packages = const [_app],
  Set<String> extraSnapshot = const {},
  Set<String>? snapshot,
}) {
  final map = PackageMap(packages);
  final graph = ImportGraph.build(
    directives: {
      for (final MapEntry(:key, :value) in files.entries)
        RepoPath(key): [for (final uri in value) _directive(key, uri)],
    },
    packages: map,
  );
  return selectAffectedTests(
    graph: graph,
    changes: ChangeSet([for (final change in changes) _change(change)]),
    packages: map,
    snapshotPaths: {
      for (final path in snapshot ?? {...files.keys, ...extraSnapshot})
        RepoPath(path),
    },
  );
}

FileChange _change(String text) {
  final kind = text[0];
  final rest = text.substring(2);
  switch (kind) {
    case 'M':
      return FileChange(path: RepoPath(rest), kind: ChangeKind.modified);
    case 'A':
      return FileChange(path: RepoPath(rest), kind: ChangeKind.added);
    case 'D':
      return FileChange(path: RepoPath(rest), kind: ChangeKind.deleted);
    case 'R':
      final [old, current] = rest.split(' -> ');
      return FileChange(
        path: RepoPath(current),
        kind: ChangeKind.renamed,
        previousPath: RepoPath(old),
      );
  }
  throw ArgumentError(text);
}

Directive _directive(String path, String written) {
  final (kind, uri) = written.startsWith('part of ')
      ? (DirectiveKind.partOf, written.substring('part of '.length))
      : written.startsWith('part ')
      ? (DirectiveKind.part, written.substring('part '.length))
      : written.startsWith('export ')
      ? (DirectiveKind.export, written.substring('export '.length))
      : (DirectiveKind.import, written);
  return Directive(
    kind: kind,
    uri: uri,
    location: Location.wholeFile(RepoPath(path)),
  );
}

List<String> values(Iterable<RepoPath> paths) => [
  for (final path in paths) path.value,
];

void main() {
  test('a changed test file selects itself', () {
    final selection = select({'test/a_test.dart': []}, ['M test/a_test.dart']);

    expect(values(selection.testFiles), ['test/a_test.dart']);
  });

  test('a test importing a changed file directly or transitively is '
      'selected', () {
    final selection = select(
      {
        'lib/a.dart': [],
        'lib/b.dart': ['a.dart'],
        'test/t_test.dart': ['../lib/b.dart'],
        'test/direct_test.dart': ['../lib/a.dart'],
      },
      ['M lib/a.dart'],
    );

    expect(values(selection.testFiles), [
      'test/direct_test.dart',
      'test/t_test.dart',
    ]);
    expect(values(selection.sources), ['lib/a.dart']);
  });

  test('package: self-imports, part files and exports are followed', () {
    final selection = select(
      {
        'lib/model.dart': ['part model.g.dart'],
        'lib/model.g.dart': ['part of model.dart'],
        'lib/api.dart': ['export src/impl.dart'],
        'lib/src/impl.dart': [],
        'test/part_test.dart': ['package:app/model.dart'],
        'test/export_test.dart': ['package:app/api.dart'],
        'test/self_test.dart': ['package:app/src/impl.dart'],
      },
      ['M lib/model.g.dart', 'M lib/src/impl.dart'],
    );

    expect(values(selection.testFiles), [
      'test/export_test.dart',
      'test/part_test.dart',
      'test/self_test.dart',
    ]);
  });

  test('a test that does not depend on any change is not selected', () {
    final selection = select(
      {
        'lib/a.dart': [],
        'lib/b.dart': [],
        'test/b_test.dart': ['../lib/b.dart'],
      },
      ['M lib/a.dart'],
    );

    expect(selection.testFiles, isEmpty);
    expect(selection.byPackage, isEmpty);
    expect(selection.closure, isEmpty);
  });

  test('a deleted source file selects the tests that still import it', () {
    final selection = select(
      {
        'lib/user.dart': ['gone.dart'],
        'test/user_test.dart': ['../lib/user.dart'],
        'test/gone_test.dart': ['../lib/gone.dart'],
        'test/other_test.dart': [],
      },
      ['D lib/gone.dart'],
    );

    expect(values(selection.testFiles), [
      'test/gone_test.dart',
      'test/user_test.dart',
    ]);
    expect(values(selection.sources), ['lib/gone.dart']);
  });

  test('a renamed source file selects the importers of its old path and its '
      'new one', () {
    final selection = select(
      {
        'lib/new.dart': [],
        'test/old_test.dart': ['../lib/old.dart'],
        'test/new_test.dart': ['../lib/new.dart'],
        'test/other_test.dart': [],
      },
      ['R lib/old.dart -> lib/new.dart'],
    );

    expect(values(selection.testFiles), [
      'test/new_test.dart',
      'test/old_test.dart',
    ]);
    expect(values(selection.sources), ['lib/new.dart', 'lib/old.dart']);
  });

  test('a deleted test file is not selected, and neither is the old path of '
      'a renamed one', () {
    final selection = select(
      {
        'lib/a.dart': [],
        'test/kept_test.dart': ['../lib/a.dart'],
        'test/new_test.dart': ['../lib/a.dart'],
        'test/gone_test.dart': ['../lib/a.dart'],
        'test/old_test.dart': ['../lib/a.dart'],
      },
      [
        'D test/gone_test.dart',
        'R test/old_test.dart -> test/new_test.dart',
        'M lib/a.dart',
      ],
      snapshot: {'lib/a.dart', 'test/kept_test.dart', 'test/new_test.dart'},
    );

    expect(values(selection.testFiles), [
      'test/kept_test.dart',
      'test/new_test.dart',
    ]);
  });

  test('a changed pubspec.yaml or analysis_options.yaml selects every test of '
      'that package and no other', () {
    final files = {
      'packages/ui/lib/ui.dart': <String>[],
      'packages/ui/test/a_test.dart': <String>[],
      'packages/ui/test/b_test.dart': ['../lib/ui.dart'],
      'packages/core/test/c_test.dart': <String>[],
      'packages/core/lib/core.dart': <String>[],
    };

    for (final changed in ['pubspec.yaml', 'analysis_options.yaml']) {
      final selection = select(
        files,
        ['M packages/ui/$changed'],
        packages: [_ui, _core],
        extraSnapshot: {'packages/ui/$changed'},
      );

      expect(values(selection.testFiles), [
        'packages/ui/test/a_test.dart',
        'packages/ui/test/b_test.dart',
      ]);
      expect(selection.byPackage.keys.single.root, RepoPath('packages/ui'));
      expect(selection.widenedBy, {
        RepoPath('packages/ui/$changed'): [_ui],
      });
    }
  });

  test('a deleted or renamed pubspec.yaml or analysis_options.yaml widens the '
      'package it belonged to', () {
    final renamed = select(
      {'packages/ui/test/a_test.dart': []},
      ['R packages/ui/pubspec.yaml -> packages/ui/pubspec.yml'],
      packages: [_ui],
    );
    final deleted = select(
      {'packages/ui/test/a_test.dart': []},
      ['D packages/ui/analysis_options.yaml'],
      packages: [_ui],
    );

    expect(values(renamed.testFiles), ['packages/ui/test/a_test.dart']);
    expect(values(deleted.testFiles), ['packages/ui/test/a_test.dart']);
    expect(renamed.widenedBy, {
      RepoPath('packages/ui/pubspec.yaml'): [_ui],
    });
    expect(deleted.widenedBy, {
      RepoPath('packages/ui/analysis_options.yaml'): [_ui],
    });
  });

  test('a pubspec.lock in the snapshot widens like a pubspec; a deleted lock '
      'selects nothing', () {
    final files = {'test/a_test.dart': <String>[], 'lib/a.dart': <String>[]};

    final modified = select(
      files,
      ['M pubspec.lock'],
      extraSnapshot: {'pubspec.lock'},
    );
    final deleted = select(files, ['D pubspec.lock']);

    expect(values(modified.testFiles), ['test/a_test.dart']);
    expect(modified.widenedBy, {
      RepoPath('pubspec.lock'): [_app],
    });
    expect(deleted.testFiles, isEmpty);
    expect(deleted.widenedBy, isEmpty);
  });

  test('a changed file outside every package selects nothing', () {
    final selection = select(
      {'packages/ui/test/a_test.dart': []},
      ['M pubspec.yaml', 'M tool/analysis_options.yaml', 'M README.md'],
      packages: [_ui],
    );

    expect(selection.testFiles, isEmpty);
    expect(selection.widenedBy, isEmpty);
  });

  test('files outside test/ ending in _test.dart are not tests', () {
    final selection = select(
      {
        'lib/a.dart': [],
        'lib/helper_test.dart': ['a.dart'],
        'tool/x_test.dart': ['../lib/a.dart'],
        'test/helper.dart': ['../lib/a.dart'],
      },
      ['M lib/a.dart'],
    );

    expect(selection.testFiles, isEmpty);
  });

  test('widening selects only the test files of the package', () {
    final selection = select(
      {'lib/a_test.dart': [], 'test/b_test.dart': []},
      ['M pubspec.yaml'],
      extraSnapshot: {'pubspec.yaml'},
    );

    expect(values(selection.testFiles), ['test/b_test.dart']);
  });

  test('the closure is the forward import closure of the tests, edge targets '
      'absent from the snapshot included', () {
    final selection = select(
      {
        'lib/a.dart': ['b.dart', 'gone.dart'],
        'lib/b.dart': [],
        'lib/unused.dart': [],
        'test/t_test.dart': ['../lib/a.dart'],
      },
      ['M lib/b.dart'],
    );

    expect(
      selection.closure.map((p) => p.value),
      containsAll([
        'test/t_test.dart',
        'lib/a.dart',
        'lib/b.dart',
        'lib/gone.dart',
      ]),
    );
    expect(selection.closure, isNot(contains(RepoPath('lib/unused.dart'))));
  });

  test('the closure holds the owning packages pubspec.yaml and '
      'analysis_options.yaml even when absent, and the lock only when in the '
      'snapshot', () {
    final selection = select(
      {
        'packages/ui/lib/ui.dart': [],
        'packages/ui/test/t_test.dart': ['../lib/ui.dart'],
        'packages/core/test/c_test.dart': [],
      },
      ['M packages/ui/lib/ui.dart'],
      packages: [_ui, _core],
      extraSnapshot: {'packages/ui/pubspec.lock', 'packages/core/pubspec.lock'},
    );

    expect(values(selection.closure), [
      'packages/ui/analysis_options.yaml',
      'packages/ui/lib/ui.dart',
      'packages/ui/pubspec.lock',
      'packages/ui/pubspec.yaml',
      'packages/ui/test/t_test.dart',
    ]);

    final withoutLock = select(
      {'packages/ui/test/t_test.dart': []},
      ['M packages/ui/test/t_test.dart'],
      packages: [_ui],
    );

    expect(values(withoutLock.closure), [
      'packages/ui/analysis_options.yaml',
      'packages/ui/pubspec.yaml',
      'packages/ui/test/t_test.dart',
    ]);
  });

  test('the closure does not hold files that merely depend on a selected '
      'test', () {
    final selection = select(
      {
        'test/t_test.dart': [],
        'test/support/all.dart': ['../t_test.dart'],
      },
      ['M test/t_test.dart'],
    );

    expect(
      selection.closure,
      isNot(contains(RepoPath('test/support/all.dart'))),
    );
    expect(selection.closure, contains(RepoPath('test/t_test.dart')));
  });

  test('results are sorted, and grouped by package with the repository root '
      'first', () {
    final selection = select(
      {
        'test/z_test.dart': ['../lib/a.dart'],
        'test/b_test.dart': ['../lib/a.dart'],
        'lib/a.dart': [],
        'packages/ui/test/y_test.dart': [],
        'packages/ui/test/a_test.dart': [],
        'packages/core/test/m_test.dart': [],
      },
      [
        'M packages/ui/test/y_test.dart',
        'M lib/a.dart',
        'M packages/core/test/m_test.dart',
        'M packages/ui/test/a_test.dart',
      ],
      packages: [_ui, _app, _core],
    );

    expect(values(selection.testFiles), [
      'packages/core/test/m_test.dart',
      'packages/ui/test/a_test.dart',
      'packages/ui/test/y_test.dart',
      'test/b_test.dart',
      'test/z_test.dart',
    ]);
    expect(selection.byPackage.keys.toList(), [_app, _core, _ui]);
    expect(values(selection.byPackage[_app]!), [
      'test/b_test.dart',
      'test/z_test.dart',
    ]);
    expect(values(selection.byPackage[_ui]!), [
      'packages/ui/test/a_test.dart',
      'packages/ui/test/y_test.dart',
    ]);
    final closure = values(selection.closure);
    expect(closure, [...closure]..sort());
  });
}

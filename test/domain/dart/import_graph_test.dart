import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/dart/import_graph.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:test/test.dart';

/// A graph of [files], each with the URIs it names. A `part ` prefix makes
/// a `part` directive, a `part of ` prefix a `part of`; anything else is an
/// `import`.
ImportGraph graph(
  Map<String, List<String>> files, {
  List<DartPackage>? packages,
}) => ImportGraph.build(
  directives: {
    for (final MapEntry(:key, :value) in files.entries)
      RepoPath(key): [for (final uri in value) _directive(key, uri)],
  },
  packages: PackageMap(
    packages ?? [const DartPackage(root: null, name: 'app')],
  ),
);

Directive _directive(String path, String written) {
  final (kind, uri) = written.startsWith('part of ')
      ? (DirectiveKind.partOf, written.substring('part of '.length))
      : written.startsWith('part ')
      ? (DirectiveKind.part, written.substring('part '.length))
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

Set<RepoPath> paths(List<String> values) => {
  for (final value in values) RepoPath(value),
};

void main() {
  test('relative, package and part URIs become edges; external ones are '
      'ignored', () {
    final g = graph({
      'lib/a.dart': [
        'b.dart',
        'package:app/src/c.dart',
        'dart:io',
        'package:http/http.dart',
      ],
      'lib/b.dart': [],
      'lib/src/c.dart': ['part c.g.dart'],
      'lib/src/c.g.dart': ['part of c.dart'],
    });

    expect(values(g.dependentsOf(paths(['lib/src/c.g.dart']))), [
      'lib/a.dart',
      'lib/src/c.dart',
      'lib/src/c.g.dart',
    ]);
    expect(values(g.dependentsOf(paths(['lib/b.dart']))), [
      'lib/a.dart',
      'lib/b.dart',
    ]);
  });

  test('a part depends on its library too', () {
    final g = graph({
      'lib/src/c.dart': ['part c.g.dart'],
      'lib/src/c.g.dart': ['part of c.dart'],
    });

    expect(values(g.dependentsOf(paths(['lib/src/c.dart']))), [
      'lib/src/c.dart',
      'lib/src/c.g.dart',
    ]);
  });

  test('package URIs resolve to the lib directory of the named package', () {
    final g = graph(
      {
        'app/lib/main.dart': ['package:ui/button.dart'],
        'packages/ui/lib/button.dart': [],
      },
      packages: [
        DartPackage(root: RepoPath('app'), name: 'app'),
        DartPackage(root: RepoPath('packages/ui'), name: 'ui'),
      ],
    );

    expect(values(g.dependentsOf(paths(['packages/ui/lib/button.dart']))), [
      'app/lib/main.dart',
      'packages/ui/lib/button.dart',
    ]);
  });

  test('a package with an empty name resolves no package URI', () {
    final g = graph(
      {
        'lib/a.dart': ['package:/b.dart'],
        'lib/b.dart': [],
      },
      packages: [const DartPackage(root: null, name: '')],
    );

    expect(values(g.dependentsOf(paths(['lib/b.dart']))), ['lib/b.dart']);
  });

  test('parent segments resolve, and a URI that leaves the repository is '
      'ignored', () {
    final g = graph({
      'test/x_test.dart': ['../lib/x.dart', '../../../outside.dart'],
      'lib/x.dart': [],
    });

    expect(values(g.dependentsOf(paths(['lib/x.dart']))), [
      'lib/x.dart',
      'test/x_test.dart',
    ]);
  });

  test('conditional imports contribute every branch', () {
    final g = graph({
      'lib/a.dart': ['stub.dart', 'io.dart'],
      'lib/io.dart': [],
      'lib/stub.dart': [],
    });

    expect(values(g.dependentsOf(paths(['lib/io.dart']))), [
      'lib/a.dart',
      'lib/io.dart',
    ]);
    expect(values(g.dependentsOf(paths(['lib/stub.dart']))), [
      'lib/a.dart',
      'lib/stub.dart',
    ]);
  });

  test('cycles terminate', () {
    final g = graph({
      'lib/a.dart': ['b.dart'],
      'lib/b.dart': ['a.dart'],
    });

    expect(values(g.dependentsOf(paths(['lib/a.dart']))), [
      'lib/a.dart',
      'lib/b.dart',
    ]);
  });

  test('importers of a file that is absent from the snapshot are still '
      'found', () {
    final g = graph({
      'lib/a.dart': ['gone.dart'],
    });

    expect(values(g.dependentsOf(paths(['lib/gone.dart']))), [
      'lib/a.dart',
      'lib/gone.dart',
    ]);
  });

  test('dependentsOf includes the inputs and is sorted', () {
    final g = graph({
      'lib/z.dart': ['m.dart'],
      'lib/a.dart': ['m.dart'],
      'lib/m.dart': [],
      'lib/q.dart': [],
    });

    expect(values(g.dependentsOf(paths(['lib/q.dart', 'lib/m.dart']))), [
      'lib/a.dart',
      'lib/m.dart',
      'lib/q.dart',
      'lib/z.dart',
    ]);
  });

  test('shortestChain is breadth-first and breaks ties by path order', () {
    final g = graph({
      'test/x_test.dart': ['../lib/b.dart', '../lib/a.dart'],
      'lib/a.dart': ['x.dart'],
      'lib/b.dart': ['x.dart'],
      'lib/x.dart': [],
    });

    final chain = g.shortestChain(
      RepoPath('lib/x.dart'),
      RepoPath('test/x_test.dart'),
    );

    expect(values(chain!), ['lib/x.dart', 'lib/a.dart', 'test/x_test.dart']);
  });

  test('shortestChain of a file to itself is that file', () {
    final g = graph({'lib/x.dart': []});

    final chain = g.shortestChain(
      RepoPath('lib/x.dart'),
      RepoPath('lib/x.dart'),
    );

    expect(values(chain!), ['lib/x.dart']);
  });

  test('shortestChain is null when unreachable', () {
    final g = graph({
      'lib/a.dart': [],
      'lib/b.dart': ['a.dart'],
    });

    expect(
      g.shortestChain(RepoPath('lib/b.dart'), RepoPath('lib/a.dart')),
      isNull,
    );
  });

  group('forward edges', () {
    test('dependenciesOf follows import, export and part edges forward, '
        'inputs included, sorted', () {
      final g = graph({
        'test/t_test.dart': ['../lib/z.dart', '../lib/a.dart'],
        'lib/a.dart': ['b.dart'],
        'lib/b.dart': ['part b.g.dart'],
        'lib/b.g.dart': ['part of b.dart'],
        'lib/z.dart': [],
        'lib/unrelated.dart': ['../test/t_test.dart'],
      });

      expect(values(g.dependenciesOf(paths(['test/t_test.dart']))), [
        'lib/a.dart',
        'lib/b.dart',
        'lib/b.g.dart',
        'lib/z.dart',
        'test/t_test.dart',
      ]);
    });

    test('edges to targets absent from the snapshot are followed and the '
        'targets are in the result', () {
      final g = graph({
        'test/t_test.dart': ['../lib/a.dart'],
        'lib/a.dart': ['gone.dart'],
      });

      expect(values(g.dependenciesOf(paths(['test/t_test.dart']))), [
        'lib/a.dart',
        'lib/gone.dart',
        'test/t_test.dart',
      ]);
    });

    test('a cycle of imports terminates', () {
      final g = graph({
        'lib/a.dart': ['b.dart'],
        'lib/b.dart': ['a.dart'],
      });

      expect(values(g.dependenciesOf(paths(['lib/a.dart']))), [
        'lib/a.dart',
        'lib/b.dart',
      ]);
    });

    test('a file the graph has never seen is its own closure', () {
      final g = graph({'lib/a.dart': []});

      expect(values(g.dependenciesOf(paths(['lib/other.dart']))), [
        'lib/other.dart',
      ]);
    });

    test('directiveOf is the first directive of the importer that resolves '
        'to the target', () {
      Location at(int line) => Location(
        RepoPath('lib/a.dart'),
        Position(line, 1),
        Position(line, 20),
      );
      final g = ImportGraph.build(
        directives: {
          RepoPath('lib/a.dart'): [
            Directive(
              kind: DirectiveKind.import,
              uri: 'dart:io',
              location: at(1),
            ),
            Directive(
              kind: DirectiveKind.import,
              uri: 'b.dart',
              location: at(2),
            ),
            Directive(
              kind: DirectiveKind.export,
              uri: 'src/../b.dart',
              location: at(3),
            ),
          ],
        },
        packages: PackageMap([const DartPackage(root: null, name: 'app')]),
      );

      expect(
        g.directiveOf(RepoPath('lib/a.dart'), RepoPath('lib/b.dart')),
        at(2),
      );
      expect(
        g.directiveOf(RepoPath('lib/a.dart'), RepoPath('lib/c.dart')),
        isNull,
      );
      expect(
        g.directiveOf(RepoPath('lib/b.dart'), RepoPath('lib/a.dart')),
        isNull,
      );
    });
  });
}

import 'package:stagelatch/src/application/packages/import_graph_builder.dart';
import 'package:stagelatch/src/application/packages/package_map_builder.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_dart_toolchain.dart';
import '../../support/fake_snapshot_files.dart';

void main() {
  test('the graph has an edge for every directive of every .dart file of the '
      'snapshot', () async {
    final snapshot = FakeSnapshotFiles({
      'pubspec.yaml': 'name: app\n',
      'lib/a.dart': "import 'b.dart';\nexport 'c.dart';\n",
      'lib/b.dart': "part 'b.part.dart';\n",
      'lib/b.part.dart': "part of 'b.dart';\n",
      'lib/c.dart': '',
      'notes.txt': 'not dart\n',
    });
    final packages = await buildPackageMap(
      snapshot,
      const StructuredDocuments(),
    );

    final graph = await buildImportGraph(
      dart: FakeDartToolchain(),
      snapshot: snapshot,
      packages: packages,
    );

    expect(
      graph.dependentsOf({RepoPath('lib/c.dart')}).map((p) => p.value),
      containsAll(['lib/a.dart', 'lib/c.dart']),
    );
    expect(
      graph.dependentsOf({RepoPath('lib/b.dart')}).map((p) => p.value),
      containsAll(['lib/a.dart', 'lib/b.dart', 'lib/b.part.dart']),
    );
    expect(
      graph.shortestChain(RepoPath('lib/b.part.dart'), RepoPath('lib/a.dart')),
      [
        RepoPath('lib/b.part.dart'),
        RepoPath('lib/b.dart'),
        RepoPath('lib/a.dart'),
      ],
    );
  });
}

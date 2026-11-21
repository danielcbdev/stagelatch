/// Builds the import graph of a snapshot (docs/specs/dart-toolchain.md, 3).
library;

import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/dart/import_graph.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// The import graph of every `.dart` file of [snapshot].
///
/// Reads facts through [dart]; that starts no analysis server. Shared by
/// the pipeline context and `why`.
Future<ImportGraph> buildImportGraph({
  required DartToolchain dart,
  required SnapshotFiles snapshot,
  required PackageMap packages,
}) async {
  final directives = {
    for (final entry in await snapshot.list())
      if (entry.path.extension == '.dart' && entry.mode.isFile)
        entry.path:
            (await dart.facts(snapshot, entry.path))?.directives ??
            const <Directive>[],
  };
  return ImportGraph.build(directives: directives, packages: packages);
}

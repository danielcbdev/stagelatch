/// The context the pipeline hands to checks.
library;

import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/packages/import_graph_builder.dart';
import 'package:stagelatch/src/application/pipeline/selection.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/dart/import_graph.dart';
import 'package:stagelatch/src/domain/dart/test_runner.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// [CheckContext] for one phase of one run.
///
/// It is a view of values the pipeline already resolved. A new one is
/// built after the fix phase, because the snapshot it exposes has changed.
final class PipelineCheckContext implements CheckContext {
  /// Creates the context of a run.
  new({
    required this.entry,
    required this.changes,
    required this.snapshot,
    required this.base,
    required this.documents,
    required this.targetBranch,
    required this.packages,
    required this.dart,
    required this.tests,
    required this._divergentAmong,
    required this._selection,
    required this._config,
  });

  final Future<Set<RepoPath>> Function(Set<RepoPath>) _divergentAmong;
  final Selection _selection;
  final Config _config;

  @override
  final EntryKind entry;

  @override
  final ChangeSet changes;

  @override
  final SnapshotFiles snapshot;

  @override
  final SnapshotFiles? base;

  @override
  final Documents documents;

  @override
  final String? targetBranch;

  @override
  final PackageMap packages;

  /// The toolchain of this phase; it starts nothing until asked.
  @override
  final DartToolchain dart;

  /// The runner of the whole run; it starts nothing until asked.
  @override
  final TestRunner tests;

  @override
  Future<Set<RepoPath>> divergentAmong(Set<RepoPath> paths) =>
      _divergentAmong(paths);

  /// Built once, from the directives of every `.dart` file of [snapshot].
  /// `facts` starts no process.
  @override
  Future<ImportGraph> get importGraph => _importGraph ??= buildImportGraph(
    dart: dart,
    snapshot: snapshot,
    packages: packages,
  );

  Future<ImportGraph>? _importGraph;

  @override
  bool isEnabled(RuleId rule) => _selection.isEnabled(rule);

  @override
  T settings<T extends Object>() => _config.settings<T>();
}

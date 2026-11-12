/// The context the pipeline hands to checks.
library;

import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/pipeline/selection.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/package_map.dart';
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
    required this._selection,
    required this._config,
  });

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

  /// No packages are known before 0.1.0, which adds package discovery.
  @override
  final PackageMap packages = PackageMap(const []);

  /// The Dart toolchain is wired in by 0.1.0. No check of this version
  /// needs it, and none may assume it exists.
  @override
  DartToolchain get dart =>
      throw UnsupportedError('The Dart toolchain arrives in 0.1.0.');

  @override
  bool isEnabled(RuleId rule) => _selection.isEnabled(rule);

  @override
  T settings<T extends Object>() => _config.settings<T>();
}

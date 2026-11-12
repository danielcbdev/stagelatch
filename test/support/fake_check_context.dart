import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

import 'fake_documents.dart';
import 'fake_snapshot_files.dart';

/// A [CheckContext] assembled from plain values, for unit-testing checks.
final class FakeCheckContext implements CheckContext {
  /// Creates a context. Everything is optional: the default is a pre-commit
  /// run over an empty snapshot with every rule enabled.
  new({
    this.entry = EntryKind.preCommit,
    ChangeSet? changes,
    SnapshotFiles? snapshot,
    this.base,
    PackageMap? packages,
    Documents? documents,
    this._dart,
    this.targetBranch,
    this._enabled,
    this._settings = const [],
  }) : changes = changes ?? ChangeSet(const []),
       snapshot = snapshot ?? FakeSnapshotFiles(const {}),
       packages = packages ?? PackageMap(const []),
       documents = documents ?? const FakeDocuments({});

  final DartToolchain? _dart;
  final Set<RuleId>? _enabled;
  final List<Object> _settings;

  /// Whether a check asked for [dart]. Lets a test assert that a check
  /// which needs no Dart knowledge never starts the toolchain.
  bool dartAccessed = false;

  @override
  final EntryKind entry;

  @override
  final ChangeSet changes;

  @override
  final SnapshotFiles snapshot;

  @override
  final SnapshotFiles? base;

  @override
  final PackageMap packages;

  @override
  final Documents documents;

  @override
  final String? targetBranch;

  @override
  DartToolchain get dart {
    dartAccessed = true;
    return _dart ?? (throw StateError('No DartToolchain was given.'));
  }

  @override
  bool isEnabled(RuleId rule) => _enabled?.contains(rule) ?? true;

  @override
  T settings<T extends Object>() {
    for (final candidate in _settings) {
      if (candidate is T) return candidate;
    }
    throw StateError('No settings of type $T were given.');
  }
}

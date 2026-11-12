/// The contract between the pipeline and a check.
library;

import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/fix.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// When a check runs within a pipeline run (ADR-0014).
enum CheckPhase {
  /// Runs first. Its fixes are written to the index before any other check
  /// looks at the snapshot.
  fix,

  /// Runs after the fix phase, against the snapshot that will be published.
  verify,
}

/// Which entry point started the run (ADR-0007).
enum EntryKind {
  /// `stagelatch run pre-commit`: the snapshot is the index.
  preCommit,

  /// `stagelatch run pre-push`: the snapshot is a pushed commit.
  prePush,

  /// `stagelatch ci`: the snapshot is the head of a pull request.
  ci,
}

/// What a check returns.
final class CheckResult {
  /// Creates a result. Both lists default to empty.
  const new({this.findings = const [], this.fixes = const []});

  /// The problems found, in any order; the pipeline sorts them.
  final List<Finding> findings;

  /// Fixes for some of [findings]. Only fix-phase checks return any.
  final List<Fix> fixes;
}

/// A group of related rules, such as `pubspec` or `format`.
///
/// A check is pure: for the same [CheckContext] answers it returns the same
/// result. It reports what it sees and decides nothing about severity
/// overrides, suppression, baseline or exit codes.
abstract interface class Check {
  /// The first part of every rule id of this check, for example `pubspec`.
  String get id;

  /// When the check runs.
  CheckPhase get phase;

  /// The rules the check can report. Empty when [hasDynamicRules] is true.
  List<RuleDescriptor> get rules;

  /// Whether rule names come from outside instead of [rules]. True only for
  /// `analyze`, whose rules are the analyzer's diagnostic codes.
  bool get hasDynamicRules;

  /// Inspects the snapshot and reports. Must honor [CheckContext.isEnabled].
  Future<CheckResult> run(CheckContext context);
}

/// Everything a check may know about the run. It deliberately has no git,
/// no file system and no clock.
abstract interface class CheckContext {
  /// Which entry point started the run.
  EntryKind get entry;

  /// The paths that changed between [base] and [snapshot].
  ChangeSet get changes;

  /// The content being judged.
  SnapshotFiles get snapshot;

  /// The other side of [changes], or null when there is none, as on the
  /// first commit of a repository.
  SnapshotFiles? get base;

  /// The Dart packages of [snapshot].
  PackageMap get packages;

  /// Parsed YAML and JSON with source locations.
  Documents get documents;

  /// Dart diagnostics, formatting and facts. Started on first access, so a
  /// check that does not need Dart must not touch it.
  DartToolchain get dart;

  /// The branch the change is headed for: the current branch on commit,
  /// the remote branch on push, the base ref in CI. Null when unknown.
  String? get targetBranch;

  /// Whether the hook's selectors enable [rule]. A check skips the work of
  /// a rule that is not enabled.
  bool isEnabled(RuleId rule);

  /// The typed parameters of the calling check, for example
  /// `AssetsSettings`.
  T settings<T extends Object>();
}

/// The `pubspec` check.
library;

import 'package:stagelatch/src/checks/pubspec/dependency_overrides.dart';
import 'package:stagelatch/src/checks/pubspec/path_dependency.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Inspects every `pubspec.yaml` and `pubspec_overrides.yaml` of the
/// changeset (docs/specs/rules.md, `pubspec`).
///
/// A pubspec that did not change is never opened: a problem that was
/// already committed is not this change's to answer for.
final class PubspecCheck implements Check {
  /// Creates the check.
  const new();

  @override
  String get id => pubspecCheckId;

  @override
  CheckPhase get phase => CheckPhase.verify;

  @override
  List<RuleDescriptor> get rules => pubspecRuleDescriptors;

  @override
  bool get hasDynamicRules => false;

  @override
  Future<CheckResult> run(CheckContext context) async {
    final findings = <Finding>[];
    // Listing the snapshot is only worth it once a path rule needs it.
    Set<RepoPath>? pubspecsInSnapshot;

    for (final change in context.changes.present) {
      final path = change.path;
      if (path.basename == pubspecOverridesFileName) {
        if (context.isEnabled(dependencyOverridesRule)) {
          findings.add(pubspecOverridesFileFinding(path));
        }
        continue;
      }
      if (path.basename != pubspecFileName) continue;

      final parsed = await context.documents.yaml(context.snapshot, path);
      switch (parsed) {
        case DocumentMissing():
          // Present in the changeset, so this cannot happen for a real
          // snapshot; there is nothing to judge either way.
          continue;
        case DocumentInvalid(:final location, :final reason):
          _addUnparseable(context, findings, location, reason);
        case DocumentParsed(:final LocatedMap root):
          final document = PubspecDocument(root);
          if (context.isEnabled(pathDependencyRule)) {
            pubspecsInSnapshot ??= await _pubspecsOf(context);
            findings.addAll(
              pathDependencyFindings(document, path, pubspecsInSnapshot),
            );
          }
          if (context.isEnabled(dependencyOverridesRule)) {
            findings.addAll(dependencyOverridesFindings(document, path));
          }
        case DocumentParsed():
          _addUnparseable(
            context,
            findings,
            Location.wholeFile(path),
            'expected a map at the top level',
          );
      }
    }
    return CheckResult(findings: findings);
  }

  void _addUnparseable(
    CheckContext context,
    List<Finding> findings,
    Location location,
    String reason,
  ) {
    if (!context.isEnabled(unparseableRule)) return;
    findings.add(
      Finding(
        rule: unparseableRule,
        severity: Severity.error,
        message: '$pubspecFileName is not valid YAML: $reason.',
        location: location,
      ),
    );
  }

  /// Every `pubspec.yaml` of the snapshot: the packages a path dependency
  /// may legitimately point at.
  Future<Set<RepoPath>> _pubspecsOf(CheckContext context) async => {
    for (final entry in await context.snapshot.list())
      if (entry.path.basename == pubspecFileName) entry.path,
  };
}

/// The `codegen` check.
library;

import 'package:stagelatch/src/checks/codegen/codegen_rules.dart';
import 'package:stagelatch/src/checks/codegen/codegen_settings.dart';
import 'package:stagelatch/src/checks/codegen/codegen_signature.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Reports a source file whose generated part was not regenerated with it
/// (docs/specs/rules.md, `codegen/stale`).
///
/// A **source file** is a changed Dart file that declares a generated part.
/// When what a generator reads from it (its signature) differs from the
/// base's, the generated part must be in the changeset too. A part the
/// snapshot does not have is reported whether or not anything changed.
///
/// A file whose facts are not well formed is left to `analyze`: its
/// declarations were never read, so it cannot be said to have changed.
final class CodegenCheck implements Check {
  /// Creates the check.
  const new();

  @override
  String get id => codegenCheckId;

  @override
  CheckPhase get phase => CheckPhase.verify;

  @override
  List<RuleDescriptor> get rules => codegenRuleDescriptors;

  @override
  bool get hasDynamicRules => false;

  @override
  Future<CheckResult> run(CheckContext context) async {
    if (!context.isEnabled(staleRule)) return const CheckResult();
    final settings = context.settings<CodegenSettings>();
    if (!settings.generatedFilesCommitted) return const CheckResult();

    final changed = {for (final change in context.changes.changes) change.path};
    final findings = <Finding>[];
    for (final change in context.changes.present) {
      final path = change.path;
      if (path.extension != '.dart') continue;
      final facts = await context.dart.facts(context.snapshot, path);
      if (facts == null || !facts.isWellFormed) continue;
      final signature = CodegenSignature.of(facts, settings.generatedSuffixes);
      if (signature.generatedParts.isEmpty) continue;

      // The base side is the file as it was before, under its old name when
      // it was renamed. A base that cannot be read makes the file new.
      CodegenSignature? before;
      final base = context.base;
      if (base != null) {
        final baseFacts = await context.dart.facts(
          base,
          change.previousPath ?? path,
        );
        if (baseFacts != null && baseFacts.isWellFormed) {
          before = CodegenSignature.of(baseFacts, settings.generatedSuffixes);
        }
      }
      final difference = signature.firstDifference(before);

      for (final part in signature.partDirectives) {
        final partPath = _resolve(path.parent, part.uri);
        if (partPath == null) continue;
        if (await context.snapshot.entry(partPath) == null) {
          findings.add(
            Finding(
              rule: staleRule,
              severity: Severity.error,
              message: '${part.uri} is declared as a part but is missing.',
              location: part.location,
            ),
          );
        } else if (difference != null && !changed.contains(partPath)) {
          findings.add(
            Finding(
              rule: staleRule,
              severity: Severity.error,
              message:
                  '"${difference.declaration ?? path.basename}" changed but '
                  '${part.uri} was not updated in this change.',
              location: difference.location ?? part.location,
            ),
          );
        }
      }
    }
    return CheckResult(findings: findings);
  }
}

/// The file a `part` URI names, relative to [directory] (null for the
/// repository root), as plain text arithmetic. Null when it climbs out of
/// the repository.
RepoPath? _resolve(RepoPath? directory, String uri) {
  final segments = [...?directory?.value.split('/')];
  for (final segment in uri.split('/')) {
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (segments.isEmpty) return null;
        segments.removeLast();
      default:
        segments.add(segment);
    }
  }
  return segments.isEmpty ? null : RepoPath(segments.join('/'));
}

/// The `l10n` check.
library;

import 'package:stagelatch/src/checks/l10n/arb_document.dart';
import 'package:stagelatch/src/checks/l10n/icu_arguments.dart';
import 'package:stagelatch/src/checks/l10n/l10n_rules.dart';
import 'package:stagelatch/src/checks/l10n/l10n_setup.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Compares the translations of each package with its template
/// (docs/specs/rules.md, `l10n`).
///
/// A package is looked at when its `l10n.yaml` changed or an `.arb` file of
/// its ARB directory changed or was deleted. All the locales of the
/// directory are then compared with the template, not only the changed
/// ones: adding a key to the template makes every translation stale.
final class L10nCheck implements Check {
  /// Creates the check.
  const new();

  @override
  String get id => l10nCheckId;

  @override
  CheckPhase get phase => CheckPhase.verify;

  @override
  List<RuleDescriptor> get rules => l10nRuleDescriptors;

  @override
  bool get hasDynamicRules => false;

  @override
  Future<CheckResult> run(CheckContext context) async {
    final changed = {for (final change in context.changes.changes) change.path};
    final present = {for (final change in context.changes.present) change.path};
    final findings = <Finding>[];
    for (final package in context.packages.packages) {
      final setup = await readL10nSetup(
        context.snapshot,
        context.documents,
        package,
      );
      if (setup == null) continue;
      final l10nYaml = RepoPath(
        package.root == null ? 'l10n.yaml' : '${package.root!.value}/l10n.yaml',
      );
      final arbChanged = changed.any(
        (path) => path.parent == setup.arbDir && path.extension == '.arb',
      );
      if (!arbChanged && !changed.contains(l10nYaml)) continue;
      findings.addAll(await _package(context, setup, present));
    }
    return CheckResult(findings: findings);
  }

  Future<List<Finding>> _package(
    CheckContext context,
    L10nSetup setup,
    Set<RepoPath> present,
  ) async {
    final findings = <Finding>[];
    final templatePath = RepoPath(
      '${setup.arbDir.value}/${setup.templateFile}',
    );

    // Every .arb file directly in the directory; null when it cannot be
    // read as an object.
    final documents = <RepoPath, ArbDocument?>{};
    for (final entry in await context.snapshot.list(under: setup.arbDir)) {
      final path = entry.path;
      if (path.parent != setup.arbDir || path.extension != '.arb') continue;
      final parsed = await context.documents.json(context.snapshot, path);
      switch (parsed) {
        case DocumentMissing():
          continue;
        case DocumentParsed(:final LocatedMap root):
          documents[path] = ArbDocument(root);
        case DocumentParsed():
          documents[path] = null;
          _unparseable(
            context,
            findings,
            present,
            path,
            Location.wholeFile(path),
            'expected an object at the top level',
          );
        case DocumentInvalid(:final location, :final reason):
          documents[path] = null;
          _unparseable(context, findings, present, path, location, reason);
      }
    }

    final template = documents[templatePath];
    if (template == null) return findings;
    final wantMissing = context.isEnabled(missingKeyRule);
    final wantMismatch = context.isEnabled(placeholderMismatchRule);
    if (!wantMissing && !wantMismatch) return findings;

    for (final MapEntry(key: path, value: translation) in documents.entries) {
      if (path == templatePath || translation == null) continue;
      for (final MapEntry(:key, value: source) in template.messages.entries) {
        final translated = translation.messages[key];
        if (translated == null) {
          if (wantMissing) {
            findings.add(
              Finding(
                rule: missingKeyRule,
                severity: Severity.error,
                message: 'Key "$key" is missing in ${path.basename}.',
                location: source.keyLocation,
              ),
            );
          }
          continue;
        }
        if (!wantMismatch) continue;
        if (source.value case LocatedScalar(value: final String expected)) {
          if (translated.value case LocatedScalar(value: final String found)) {
            final wanted = icuArguments(expected);
            final got = icuArguments(found);
            if (wanted.length != got.length || !wanted.containsAll(got)) {
              findings.add(
                Finding(
                  rule: placeholderMismatchRule,
                  severity: Severity.error,
                  message:
                      'Placeholders of "$key" differ from the template: '
                      'expected ${_names(wanted)}, found ${_names(got)}.',
                  location: translated.keyLocation,
                ),
              );
            }
          }
        }
      }
    }
    return findings;
  }

  /// Reports an unreadable `.arb` file, when it is one that changed: a
  /// file that was already broken is not this change's to answer for.
  void _unparseable(
    CheckContext context,
    List<Finding> findings,
    Set<RepoPath> present,
    RepoPath path,
    Location location,
    String reason,
  ) {
    if (!present.contains(path) || !context.isEnabled(unparseableRule)) return;
    findings.add(
      Finding(
        rule: unparseableRule,
        severity: Severity.error,
        message: '${path.basename} is not valid JSON: $reason.',
        location: location,
      ),
    );
  }
}

/// `{a, b}`: the [names] sorted, in braces.
String _names(Set<String> names) => '{${(names.toList()..sort()).join(', ')}}';

/// The `l10n/unused-key` rule (docs/specs/rules.md, `l10n`).
library;

import 'package:stagelatch/src/checks/codegen/codegen_settings.dart';
import 'package:stagelatch/src/checks/l10n/arb_document.dart';
import 'package:stagelatch/src/checks/l10n/l10n_rules.dart';
import 'package:stagelatch/src/checks/l10n/l10n_setup.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The keys of [template] that no non-generated Dart file of [package]
/// mentions, in template order.
///
/// A key is used when its name is among the `identifiers` of a file:
/// `l10n.key`, `AppLocalizations.of(context).key` and `'${l10n.key}'` all
/// are. The whole package is scanned, not the changeset: whether a key is
/// used depends on every file, which is why this is the one rule that is not
/// change-aware. Scanned files are the `.dart` files the snapshot has whose
/// nearest package is [package], except those under the l10n output
/// directory and those ending in a `codegen.generated_suffixes` suffix: the
/// generated localizations declare every key, and would use them all.
/// When `l10n.yaml` has no `output-dir`, Flutter writes those files into
/// `arb-dir`, so that directory is excluded the same way.
///
/// A file whose facts are not well formed, or cannot be read, has no
/// identifiers, and an empty set must not be read as "no uses": the package
/// then produces no finding, and `analyze` reports the syntax error.
Future<List<Finding>> unusedKeyFindings(
  CheckContext context,
  L10nSetup setup,
  ArbDocument template,
  DartPackage package,
) async {
  if (template.messages.isEmpty) return const [];
  final suffixes = context.settings<CodegenSettings>().generatedSuffixes;
  // Flutter gen-l10n writes into arb-dir when output-dir is omitted.
  final generatedDir = setup.outputDir ?? setup.arbDir;

  final paths = [
    for (final entry in await context.snapshot.list())
      if (entry.mode.isFile &&
          entry.path.extension == '.dart' &&
          context.packages.packageOf(entry.path) == package &&
          !entry.path.isWithin(generatedDir) &&
          !suffixes.any(entry.path.value.endsWith))
        entry.path,
  ];
  final scanned = await Future.wait([
    for (final path in paths) context.dart.facts(context.snapshot, path),
  ]);

  final used = <String>{};
  for (final facts in scanned) {
    if (facts == null || !facts.isWellFormed) return const [];
    used.addAll(facts.identifiers);
  }

  return [
    for (final MapEntry(:key, :value) in template.messages.entries)
      if (!used.contains(key))
        Finding(
          rule: unusedKeyRule,
          severity: Severity.warning,
          message: 'Key "$key" is not referenced by any Dart file.',
          location: value.keyLocation,
        ),
  ];
}

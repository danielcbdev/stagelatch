/// The `format` check (docs/specs/rules.md, `format`).
library;

import 'package:stagelatch/src/checks/format/first_difference.dart';
import 'package:stagelatch/src/checks/format/format_settings.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/fix.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// A changed Dart file that `dart format` of the project's SDK would change.
const RuleId unformattedRule = RuleId('format', 'unformatted');

/// Formats every changed Dart file and reports, with the formatted text as
/// a fix, those whose text would change. Whether the fix is applied is the
/// pipeline's decision (ADR-0014): only on the index, and not with
/// `--no-fix`.
final class FormatCheck implements Check {
  /// Creates the check.
  const new();

  @override
  String get id => 'format';

  @override
  CheckPhase get phase => CheckPhase.fix;

  @override
  List<RuleDescriptor> get rules => const [
    RuleDescriptor(
      id: unformattedRule,
      defaultSeverity: Severity.error,
      summary: 'A Dart file is not formatted.',
      fixable: true,
    ),
  ];

  @override
  bool get hasDynamicRules => false;

  @override
  Future<CheckResult> run(CheckContext context) async {
    if (!context.isEnabled(unformattedRule)) return const CheckResult();
    final paths = <RepoPath>[];
    final sources = <String>[];
    for (final change in context.changes.present) {
      if (change.path.extension != '.dart') continue;
      final entry = await context.snapshot.entry(change.path);
      if (entry == null || !entry.mode.isFile) continue;
      final text = await context.snapshot.readText(change.path);
      if (text == null) continue;
      paths.add(change.path);
      sources.add(text);
    }
    if (paths.isEmpty) return const CheckResult();

    final dart = context.dart;
    // Formatted concurrently; the results are consumed by index, so the
    // order of the findings never depends on which finished first.
    final outcomes = await Future.wait([
      for (final (index, path) in paths.indexed)
        dart.format(path, sources[index]),
    ]);
    final fix = context.settings<FormatSettings>().fix;
    final findings = <Finding>[];
    final fixes = <Fix>[];
    for (final (index, outcome) in outcomes.indexed) {
      final source = sources[index];
      // A file that does not parse is `analyze`'s to report.
      if (outcome is! Formatted || outcome.text == source) continue;
      final path = paths[index];
      final at = firstDifference(source, outcome.text);
      findings.add(
        Finding(
          rule: unformattedRule,
          severity: Severity.error,
          message: 'File is not formatted.',
          location: Location(path, at, at),
        ),
      );
      if (fix) {
        fixes.add(
          Fix(rule: unformattedRule, path: path, content: outcome.text),
        );
      }
    }
    return CheckResult(findings: findings, fixes: fixes);
  }
}

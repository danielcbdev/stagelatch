/// The `tests` check.
library;

import 'package:stagelatch/src/checks/tests/test_key.dart';
import 'package:stagelatch/src/checks/tests/tests_rules.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Looks at the tests of the test files that changed (docs/specs/rules.md,
/// `tests`).
///
/// `tests/solo` reports every `solo` argument. `tests/new-skip` reports
/// skips this change introduced: for each test key, the skipped calls of
/// the file are counted against the skipped calls of its base version, and
/// when there are more, the later ones in source order are reported. A file
/// that did not change is not looked at, so an old skip never blocks anyone.
///
/// A file whose facts are not well formed is left to `analyze`. A base that
/// is absent, or cannot be read, makes every skip new.
final class TestsCheck implements Check {
  /// Creates the check.
  const new();

  @override
  String get id => testsCheckId;

  @override
  CheckPhase get phase => CheckPhase.verify;

  @override
  List<RuleDescriptor> get rules => testsRuleDescriptors;

  @override
  bool get hasDynamicRules => false;

  @override
  Future<CheckResult> run(CheckContext context) async {
    final wantSolo = context.isEnabled(soloRule);
    final wantSkip = context.isEnabled(newSkipRule);
    if (!wantSolo && !wantSkip) return const CheckResult();

    final findings = <Finding>[];
    for (final change in context.changes.present) {
      final path = change.path;
      if (!isTestFile(path, context.packages)) continue;
      final facts = await context.dart.facts(context.snapshot, path);
      if (facts == null || !facts.isWellFormed) continue;

      if (wantSolo) {
        for (final call in facts.testCalls) {
          final solo = call.solo;
          if (solo == null) continue;
          findings.add(
            Finding(
              rule: soloRule,
              severity: Severity.error,
              message:
                  '"solo" must not be committed: it silently skips every '
                  'other test.',
              location: solo,
            ),
          );
        }
      }

      if (wantSkip) {
        final skipped = [
          for (final call in facts.testCalls)
            if (call.skip != null) call,
        ];
        if (skipped.isEmpty) continue;
        final before = await _skippedInBase(
          context,
          change.previousPath ?? path,
        );
        // The n-th skipped call of a key is new when the base had fewer
        // than n of them, which reports the later ones.
        final seen = <String, int>{};
        for (final call in skipped) {
          final key = testKey(call);
          final index = seen.update(key, (n) => n + 1, ifAbsent: () => 0);
          if (index < (before[key] ?? 0)) continue;
          findings.add(
            Finding(
              rule: newSkipRule,
              severity: Severity.warning,
              message: 'Test "${call.description}" was skipped in this change.',
              location: call.skip!,
            ),
          );
        }
      }
    }
    return CheckResult(findings: findings);
  }

  /// How many skipped calls of each key the base version of [path] had;
  /// empty when there is no readable base.
  Future<Map<String, int>> _skippedInBase(
    CheckContext context,
    RepoPath path,
  ) async {
    final base = context.base;
    if (base == null) return const {};
    final facts = await context.dart.facts(base, path);
    if (facts == null || !facts.isWellFormed) return const {};
    final counts = <String, int>{};
    for (final call in facts.testCalls) {
      if (call.skip == null) continue;
      counts.update(testKey(call), (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}

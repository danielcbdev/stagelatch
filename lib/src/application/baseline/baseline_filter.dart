/// Applying a baseline to findings
/// (docs/specs/baseline-and-suppression.md section 4.3).
library;

import 'package:stagelatch/src/application/baseline/baseline.dart';
import 'package:stagelatch/src/application/baseline/fingerprint.dart';
import 'package:stagelatch/src/application/pipeline/inline_ignore.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// What is left of a run after the baseline.
final class BaselineOutcome {
  /// Creates the outcome.
  const new({required this.kept, required this.baselined});

  /// The findings the baseline did not absorb, in their original order.
  final List<Finding> kept;

  /// How many findings it absorbed.
  final int baselined;
}

/// Removes the findings [baseline] accepts.
///
/// [findings] must already be sorted with `Finding.compare`: counts are
/// consumed in that order, so which of several identical findings is
/// reported never depends on the order checks ran in. A finding is
/// absorbed when an entry has the same rule, path and fingerprint and
/// still has count left. `stagelatch/invalid-ignore` is never absorbed.
Future<BaselineOutcome> applyBaseline(
  List<Finding> findings,
  Baseline baseline,
  SnapshotFiles snapshot,
) async {
  if (baseline.entries.isEmpty) {
    return BaselineOutcome(kept: findings, baselined: 0);
  }
  final remaining = {
    for (final entry in baseline.entries)
      (entry.rule, entry.path, entry.fingerprint): entry.count,
  };
  final kept = <Finding>[];
  var baselined = 0;
  for (final finding in findings) {
    if (finding.rule == invalidIgnoreRule) {
      kept.add(finding);
      continue;
    }
    final key = (
      finding.rule,
      finding.location.path,
      await fingerprintOf(finding, snapshot),
    );
    final left = remaining[key] ?? 0;
    if (left > 0) {
      remaining[key] = left - 1;
      baselined++;
    } else {
      kept.add(finding);
    }
  }
  return BaselineOutcome(kept: kept, baselined: baselined);
}

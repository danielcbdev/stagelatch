/// The filters between what checks report and what the user sees.
///
/// They are pure functions, applied in a fixed order
/// (docs/specs/baseline-and-suppression.md, section 1): selection, levels,
/// exclude. Inline ignores and the baseline join the chain in later
/// versions, after these.
library;

import 'package:glob/glob.dart';
import 'package:stagelatch/src/application/pipeline/selection.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Drops findings of rules that [selection] does not enable.
///
/// Checks are asked to honor the selection themselves; this is the
/// guarantee that a rule the hook did not ask for is never reported.
List<Finding> applySelection(List<Finding> findings, Selection selection) => [
  for (final finding in findings)
    if (selection.isEnabled(finding.rule)) finding,
];

/// Applies the `rules:` map: [RuleLevel.off] drops a finding, the other
/// levels replace its severity. A rule without a level is left as reported.
List<Finding> applyLevels(
  List<Finding> findings,
  Map<RuleId, RuleLevel> levels,
) {
  final result = <Finding>[];
  for (final finding in findings) {
    final level = levels[finding.rule];
    if (level == null) {
      result.add(finding);
      continue;
    }
    final severity = level.severity;
    // A level without a severity is `off`: the finding is dropped.
    if (severity == null) continue;
    result.add(
      Finding(
        rule: finding.rule,
        severity: severity,
        message: finding.message,
        location: finding.location,
      ),
    );
  }
  return result;
}

/// Drops findings whose path matches one of the [exclude] globs.
List<Finding> applyExclude(List<Finding> findings, List<Glob> exclude) => [
  for (final finding in findings)
    if (!exclude.any((glob) => glob.matches(finding.location.path.value)))
      finding,
];

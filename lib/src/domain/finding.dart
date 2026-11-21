/// What a check reports.
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// One problem a rule found in the snapshot.
///
/// A check reports what it sees. Severity overrides, suppression, baseline
/// and the exit code are decided later, by the pipeline.
@immutable
final class Finding {
  /// Creates a finding.
  const new({
    required this.rule,
    required this.severity,
    required this.message,
    required this.location,
    this.severityLocked = false,
  });

  /// The rule that produced the finding.
  final RuleId rule;

  /// How serious it is. Only [Severity.error] blocks.
  final Severity severity;

  /// The sentence shown to the user, exactly as the rule catalog words it.
  final String message;

  /// Where the problem is.
  final Location location;

  /// Whether `rules:` may change [severity]. A locked finding can still be
  /// dropped by `off`, an exclude, an inline ignore or the baseline, but is
  /// never raised or lowered. Only the dirty-skip warning of
  /// `tests/affected` sets it: a skip is not a failure, whatever level the
  /// rule has for real failures.
  final bool severityLocked;

  /// The one order in which findings are reported: by path, start position,
  /// rule, then message.
  ///
  /// Reports are sorted with this, never left in the order checks happened
  /// to finish, so the same snapshot always yields the same output
  /// (ADR-0003).
  static int compare(Finding a, Finding b) {
    final byPath = a.location.path.compareTo(b.location.path);
    if (byPath != 0) return byPath;
    final byStart = a.location.start.compareTo(b.location.start);
    if (byStart != 0) return byStart;
    final byRule = a.rule.compareTo(b.rule);
    if (byRule != 0) return byRule;
    return a.message.compareTo(b.message);
  }

  @override
  bool operator ==(Object other) =>
      other is Finding &&
      other.rule == rule &&
      other.severity == severity &&
      other.message == message &&
      other.location == location &&
      other.severityLocked == severityLocked;

  @override
  int get hashCode =>
      Object.hash(rule, severity, message, location, severityLocked);

  @override
  String toString() => '$location ${severity.name} $rule: $message';
}

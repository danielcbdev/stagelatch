/// Severities of findings and the levels a rule can be configured to.
library;

/// How serious a finding is. Only [error] blocks.
enum Severity {
  /// Reported, never blocking.
  warning,

  /// Blocks the commit, the push or the CI run.
  error,
}

/// What the `rules:` map of the configuration can set a rule to (ADR-0009).
enum RuleLevel {
  /// The rule's findings are dropped.
  off(null),

  /// The rule's findings are reported as [Severity.warning].
  warning(Severity.warning),

  /// The rule's findings are reported as [Severity.error].
  error(Severity.error);

  new(this.severity);

  /// The severity this level forces, or null for [off].
  final Severity? severity;
}

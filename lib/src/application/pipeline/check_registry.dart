/// The checks of the running version.
library;

import 'package:stagelatch/src/application/config/check_catalog.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/rule_id.dart';

/// Every check the tool has, in the one order that reports use.
///
/// The order decides how the check table of a report is laid out and in
/// which sequence fix-phase checks run. It never affects which findings a
/// run produces.
final class CheckRegistry implements CheckCatalog {
  /// Creates a registry of [checks], in the order given.
  ///
  /// Throws [ArgumentError] when two checks share an id, or when a check
  /// declares a rule that does not start with its own id.
  factory(List<Check> checks) {
    final descriptors = <RuleId, RuleDescriptor>{};
    final ids = <String>{};
    for (final check in checks) {
      if (!ids.add(check.id)) {
        throw ArgumentError('Two checks are named "${check.id}".');
      }
      for (final rule in check.rules) {
        if (rule.id.check != check.id) {
          throw ArgumentError(
            'Check "${check.id}" declares the foreign rule "${rule.id}".',
          );
        }
        descriptors[rule.id] = rule;
      }
    }
    return CheckRegistry._(List.unmodifiable(checks), descriptors);
  }

  const new _(this.checks, this._descriptors);

  /// The checks, in registry order. Unmodifiable.
  final List<Check> checks;

  final Map<RuleId, RuleDescriptor> _descriptors;

  @override
  Set<String> get checkIds => {for (final check in checks) check.id};

  @override
  bool hasRule(RuleId id) => _descriptors.containsKey(id);

  @override
  bool hasDynamicRules(String check) => checks.any(
    (candidate) => candidate.id == check && candidate.hasDynamicRules,
  );

  /// What the owning check declares about [id], or null when no check
  /// declares it, as for the open-ended rules of `analyze`.
  RuleDescriptor? descriptorOf(RuleId id) => _descriptors[id];
}

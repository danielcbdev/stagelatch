/// Which checks and rules a hook enables.
library;

import 'package:stagelatch/src/application/config/hook_selector.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/rule_id.dart';

/// The rules enabled by the selectors of one hook.
///
/// A whole-check selector enables every rule of that check, including rule
/// names nobody declared in advance, which is what `analyze` needs: its
/// rules are whatever diagnostic codes the analyzer reports.
final class Selection {
  /// Builds the selection of [selectors].
  factory of(Iterable<HookSelector> selectors) {
    final checks = <String>{};
    final rules = <RuleId>{};
    for (final selector in selectors) {
      switch (selector.ruleId) {
        case final rule?:
          rules.add(rule);
        case null:
          checks.add(selector.check);
      }
    }
    return Selection._(checks, rules);
  }

  const new _(this._checks, this._rules);

  /// Checks selected whole.
  final Set<String> _checks;

  /// Rules selected one by one.
  final Set<RuleId> _rules;

  /// Whether [rule] is enabled, by its check or by itself.
  bool isEnabled(RuleId rule) =>
      _checks.contains(rule.check) || _rules.contains(rule);

  /// Whether [check] has anything to do: it is selected whole, or at least
  /// one of its rules is.
  bool runs(Check check) =>
      _checks.contains(check.id) ||
      _rules.any((rule) => rule.check == check.id);
}

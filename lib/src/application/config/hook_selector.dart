/// One element of a hook's list in the configuration.
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/rule_id.dart';

/// Selects what a hook runs: a whole check (`pubspec`) or one rule
/// (`tests/solo`). It uses the same notation as rule ids (ADR-0009).
@immutable
final class HookSelector {
  /// Creates a selector for [check], narrowed to [rule] when given.
  const new(this.check, [this.rule]);

  /// Parses `<check>` or `<check>/<rule>`.
  ///
  /// Throws [FormatException] for anything else.
  factory parse(String value) {
    final parts = value.split('/');
    if (parts.length > 2 || !parts.every(_part.hasMatch)) {
      throw FormatException('Expected <check> or <check>/<rule>.', value);
    }
    return HookSelector(parts[0], parts.length == 2 ? parts[1] : null);
  }

  /// One part of a selector; the same shape as a part of a rule id. A
  /// single character class under one quantifier, so matching is linear
  /// (security rule S6).
  static final _part = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

  /// The check to run.
  final String check;

  /// The one rule to enable, or null to enable every rule of [check].
  final String? rule;

  /// The rule this selector names, or null when it selects a whole check.
  RuleId? get ruleId => switch (rule) {
    final name? => RuleId(check, name),
    null => null,
  };

  @override
  bool operator ==(Object other) =>
      other is HookSelector && other.check == check && other.rule == rule;

  @override
  int get hashCode => Object.hash(check, rule);

  @override
  String toString() => rule == null ? check : '$check/$rule';
}

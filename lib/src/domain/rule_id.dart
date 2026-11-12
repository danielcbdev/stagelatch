/// Rule identifiers and their descriptions.
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The identifier of a rule: `<check>/<rule>`, e.g. `pubspec/path-dependency`.
///
/// This is the only name a rule has. The same string appears in hook lists,
/// the `rules:` map, `stagelatch:ignore` comments, the baseline and every
/// report (ADR-0009).
@immutable
final class RuleId implements Comparable<RuleId> {
  /// Creates an id from parts that are already known to be valid.
  ///
  /// Use [RuleId.parse] for text that comes from a user or a file.
  const new(this.check, this.rule);

  /// Parses `<check>/<rule>`.
  ///
  /// Each part starts with a lowercase letter or digit and continues with
  /// lowercase letters, digits, `-` or `_`. The underscore exists because
  /// `analyze` rules keep the analyzer's spelling (`analyze/unused_import`).
  ///
  /// Throws [FormatException] for anything else.
  factory parse(String value) {
    final parts = value.split('/');
    if (parts.length != 2 ||
        !_part.hasMatch(parts[0]) ||
        !_part.hasMatch(parts[1])) {
      throw FormatException('Expected <check>/<rule>.', value);
    }
    return RuleId(parts[0], parts[1]);
  }

  /// One part of an id. A single character class under one quantifier, so
  /// matching is linear in the input (security rule S6).
  static final _part = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

  /// The check that owns the rule, e.g. `pubspec`.
  final String check;

  /// The rule's name within its check, e.g. `path-dependency`.
  final String rule;

  /// Orders by [check], then by [rule].
  @override
  int compareTo(RuleId other) {
    final byCheck = check.compareTo(other.check);
    return byCheck != 0 ? byCheck : rule.compareTo(other.rule);
  }

  @override
  bool operator ==(Object other) =>
      other is RuleId && other.check == check && other.rule == rule;

  @override
  int get hashCode => Object.hash(check, rule);

  @override
  String toString() => '$check/$rule';
}

/// What a check declares about one of its rules.
final class RuleDescriptor {
  /// Creates a descriptor.
  const new({
    required this.id,
    required this.defaultSeverity,
    required this.summary,
    this.fixable = false,
  });

  /// The rule being described.
  final RuleId id;

  /// The severity used when the configuration does not override it.
  final Severity defaultSeverity;

  /// One sentence saying what the rule reports, for rule listings.
  final String summary;

  /// Whether the check can produce a fix for this rule's findings.
  final bool fixable;
}

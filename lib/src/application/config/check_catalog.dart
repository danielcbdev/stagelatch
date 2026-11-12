/// What the configuration loader needs to know about the available checks.
library;

import 'package:stagelatch/src/domain/rule_id.dart';

/// The checks and rules of the running version.
///
/// The loader validates selectors and rule ids against it, so that a typo
/// or a rule from a newer version is rejected instead of silently doing
/// nothing.
abstract interface class CheckCatalog {
  /// The ids of every available check, for example `pubspec`.
  Set<String> get checkIds;

  /// Whether [id] is a rule that some check declares.
  bool hasRule(RuleId id);

  /// Whether [check] accepts any rule name. True only for `analyze`, whose
  /// rules are the analyzer's diagnostic codes.
  bool hasDynamicRules(String check);
}

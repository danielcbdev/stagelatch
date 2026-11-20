/// The rules of the `tests` check (docs/specs/rules.md).
library;

import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The id of the check, and the first part of each of its rule ids.
const String testsCheckId = 'tests';

/// A `solo` argument, which silently skips every other test.
const RuleId soloRule = RuleId(testsCheckId, 'solo');

/// A test or group skipped in this change.
const RuleId newSkipRule = RuleId(testsCheckId, 'new-skip');

/// What the check declares about its rules, in catalog order. `affected` is
/// registered by plan 04, not here.
const List<RuleDescriptor> testsRuleDescriptors = [
  RuleDescriptor(
    id: soloRule,
    defaultSeverity: Severity.error,
    summary: 'A test uses solo, which skips every other test.',
  ),
  RuleDescriptor(
    id: newSkipRule,
    defaultSeverity: Severity.warning,
    summary: 'A test was skipped in this change.',
  ),
];

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

/// The tests that a change can affect, run on pre-push and in `ci`.
const RuleId affectedRule = RuleId(testsCheckId, 'affected');

/// What the check declares about its rules, in catalog order.
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
  RuleDescriptor(
    id: affectedRule,
    defaultSeverity: Severity.error,
    summary:
        'A test affected by the change fails, or cannot be run. '
        'Runs on pre-push and ci only.',
  ),
];

/// The rules of the `l10n` check (docs/specs/rules.md).
library;

import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The id of the check, and the first part of each of its rule ids.
const String l10nCheckId = 'l10n';

/// A message of the template that a translation does not have.
const RuleId missingKeyRule = RuleId(l10nCheckId, 'missing-key');

/// A translation whose placeholders differ from the template's.
const RuleId placeholderMismatchRule = RuleId(
  l10nCheckId,
  'placeholder-mismatch',
);

/// An `.arb` file that is not a JSON object.
const RuleId unparseableRule = RuleId(l10nCheckId, 'unparseable');

/// What the check declares about its rules, in catalog order.
const List<RuleDescriptor> l10nRuleDescriptors = [
  RuleDescriptor(
    id: missingKeyRule,
    defaultSeverity: Severity.error,
    summary: 'A message of the template is missing in a translation.',
  ),
  RuleDescriptor(
    id: placeholderMismatchRule,
    defaultSeverity: Severity.error,
    summary: 'A translation has different placeholders than the template.',
  ),
  RuleDescriptor(
    id: unparseableRule,
    defaultSeverity: Severity.error,
    summary: 'An ARB file is not a valid JSON object.',
  ),
];

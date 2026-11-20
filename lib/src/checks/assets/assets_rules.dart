/// The rules of the `assets` check (docs/specs/rules.md).
library;

import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The id of the check, and the first part of each of its rule ids.
const String assetsCheckId = 'assets';

/// A declared asset that is not in the snapshot.
const RuleId missingRule = RuleId(assetsCheckId, 'missing');

/// A changed file under an asset root that `pubspec.yaml` does not declare.
const RuleId undeclaredRule = RuleId(assetsCheckId, 'undeclared');

/// A changed file under an asset root that is larger than the limit.
const RuleId maxFileSizeRule = RuleId(assetsCheckId, 'max-file-size');

/// What the check declares about its rules, in catalog order.
const List<RuleDescriptor> assetsRuleDescriptors = [
  RuleDescriptor(
    id: missingRule,
    defaultSeverity: Severity.error,
    summary: 'A declared asset does not exist.',
  ),
  RuleDescriptor(
    id: undeclaredRule,
    defaultSeverity: Severity.error,
    summary: 'A file under an asset root is not declared in pubspec.yaml.',
  ),
  RuleDescriptor(
    id: maxFileSizeRule,
    defaultSeverity: Severity.error,
    summary: 'An asset is larger than the configured limit.',
  ),
];

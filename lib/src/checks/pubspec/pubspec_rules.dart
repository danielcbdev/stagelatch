/// The rules of the `pubspec` check (docs/specs/rules.md).
library;

import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The id of the check, and the first part of each of its rule ids.
const String pubspecCheckId = 'pubspec';

/// A dependency that points at a local path which is not a package of this
/// repository.
const RuleId pathDependencyRule = RuleId(pubspecCheckId, 'path-dependency');

/// A committed `dependency_overrides` section or `pubspec_overrides.yaml`.
const RuleId dependencyOverridesRule = RuleId(
  pubspecCheckId,
  'dependency-overrides',
);

/// A `pubspec.yaml` that cannot be read as a YAML map.
const RuleId unparseableRule = RuleId(pubspecCheckId, 'unparseable');

/// What the check declares about its rules, in catalog order.
const List<RuleDescriptor> pubspecRuleDescriptors = [
  RuleDescriptor(
    id: pathDependencyRule,
    defaultSeverity: Severity.error,
    summary:
        'A dependency uses a local path that is not a package of this '
        'repository.',
  ),
  RuleDescriptor(
    id: dependencyOverridesRule,
    defaultSeverity: Severity.error,
    summary: 'Dependency overrides are being committed.',
  ),
  RuleDescriptor(
    id: unparseableRule,
    defaultSeverity: Severity.error,
    summary: 'A pubspec.yaml is not a valid YAML map.',
  ),
];

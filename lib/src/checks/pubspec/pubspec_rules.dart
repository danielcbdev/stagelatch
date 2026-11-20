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

/// A git dependency with no `ref`, or, with `require_sha`, with a `ref`
/// that is not a full commit id.
const RuleId unpinnedGitRule = RuleId(pubspecCheckId, 'unpinned-git');

/// A `version` lower than the one in the base, on a branch that must only
/// grow.
const RuleId buildNumberRegressionRule = RuleId(
  pubspecCheckId,
  'build-number-regression',
);

/// A `pubspec.lock` that no longer follows its `pubspec.yaml`.
const RuleId lockfileOutOfSyncRule = RuleId(
  pubspecCheckId,
  'lockfile-out-of-sync',
);

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
  RuleDescriptor(
    id: unpinnedGitRule,
    defaultSeverity: Severity.error,
    summary: 'A git dependency is not pinned to a ref.',
  ),
  RuleDescriptor(
    id: buildNumberRegressionRule,
    defaultSeverity: Severity.error,
    summary: 'The version is lower than the one in the base.',
  ),
  RuleDescriptor(
    id: lockfileOutOfSyncRule,
    defaultSeverity: Severity.error,
    summary: 'pubspec.lock does not follow pubspec.yaml.',
  ),
];

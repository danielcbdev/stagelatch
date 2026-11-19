/// The `pubspec/dependency-overrides` rule.
library;

import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The name of the file pub reads overrides from without touching the
/// pubspec. It is meant to stay local.
const String pubspecOverridesFileName = 'pubspec_overrides.yaml';

/// Reports a non-empty `dependency_overrides` section of [document], the
/// pubspec at [pubspecPath].
///
/// An override is a temporary local patch to dependency resolution. Once
/// committed it silently changes what everyone else builds with.
List<Finding> dependencyOverridesFindings(
  PubspecDocument document,
  RepoPath pubspecPath,
) {
  final names = document.overrideNames.toList()..sort();
  final section = document.overrides;
  if (section == null || names.isEmpty) return const [];
  return [
    Finding(
      rule: dependencyOverridesRule,
      severity: Severity.error,
      message:
          '${PubspecDocument.overridesKey} must not be committed: '
          '${names.join(', ')}.',
      location: section.keyLocation,
    ),
  ];
}

/// The finding for a committed `pubspec_overrides.yaml` at [path].
Finding pubspecOverridesFileFinding(RepoPath path) => Finding(
  rule: dependencyOverridesRule,
  severity: Severity.error,
  message: '$pubspecOverridesFileName must not be committed.',
  location: Location.wholeFile(path),
);

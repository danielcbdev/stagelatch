/// The `pubspec/build-number-regression` rule.
library;

import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Reports a `version` that is lower than the one in [base].
///
/// Release pipelines publish by version, so a version that goes backwards
/// on a release branch is a build that can never be uploaded. The rule
/// reports it when:
///
/// - the version, ignoring the build number, is lower by semantic version
///   ordering; or
/// - it is equal and the build number is lower, or the base had a build
///   number and [snapshot] has none.
///
/// Build segments are compared as integers when both are, otherwise as
/// text. With no [base], or when either side has no `version` that parses,
/// there is nothing to compare and nothing is reported. The caller decides
/// whether the rule applies to the branch at all.
List<Finding> buildNumberRegressionFindings({
  required PubspecDocument snapshot,
  required PubspecDocument? base,
  required RepoPath path,
}) {
  if (base == null) return const [];
  final now = _versionOf(snapshot);
  final before = _versionOf(base);
  if (now == null || before == null) return const [];
  if (!_isLower(now.version, before.version)) return const [];
  return [
    Finding(
      rule: buildNumberRegressionRule,
      severity: Severity.error,
      message: 'Version went backwards: ${before.text} -> ${now.text}.',
      location: now.location,
    ),
  ];
}

/// The `version` of [document] as written and as parsed, or null when it is
/// absent or is not a semantic version.
({String text, Version version, Location location})? _versionOf(
  PubspecDocument document,
) {
  if (document.root.entries['version']?.value case LocatedScalar(
    value: final String text,
    :final location,
  )) {
    try {
      return (text: text, version: Version.parse(text), location: location);
    } on FormatException {
      return null;
    }
  }
  return null;
}

/// Whether [now] is lower than [before], ordering builds as the rule says.
bool _isLower(Version now, Version before) {
  final byRelease = _withoutBuild(now).compareTo(_withoutBuild(before));
  if (byRelease != 0) return byRelease < 0;
  if (before.build.isEmpty) return false;
  if (now.build.isEmpty) return true;
  final shared = now.build.length < before.build.length
      ? now.build.length
      : before.build.length;
  for (var i = 0; i < shared; i++) {
    final a = now.build[i];
    final b = before.build[i];
    final order = a is int && b is int ? a.compareTo(b) : '$a'.compareTo('$b');
    if (order != 0) return order < 0;
  }
  return now.build.length < before.build.length;
}

Version _withoutBuild(Version version) => Version(
  version.major,
  version.minor,
  version.patch,
  pre: version.preRelease.isEmpty ? null : version.preRelease.join('.'),
);

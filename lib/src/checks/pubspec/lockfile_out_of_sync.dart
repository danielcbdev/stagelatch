/// The `pubspec/lockfile-out-of-sync` rule.
library;

import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/checks/pubspec/lockfile_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Reports where [lock] no longer follows [pubspec].
///
/// This is a cheap consistency check, not version solving: a dependency the
/// lock does not have, one whose source kind differs, a hosted dependency
/// whose locked version its constraint does not allow, and a direct entry
/// of the lock that the pubspec does not declare. Transitive dependencies
/// are not looked at, and git, path and SDK dependencies are compared by
/// source only. A constraint or version that does not parse is skipped.
///
/// A dependency that is also under `dependency_overrides` is not compared:
/// the override decides what the lock resolves, and has its own rule.
/// [pubspecPath] is where [pubspec] lives, for the locations.
List<Finding> lockfileFindings({
  required PubspecDocument pubspec,
  required LockfileDocument lock,
  required RepoPath pubspecPath,
}) {
  final findings = <Finding>[];
  final overridden = pubspec.overrideNames.toSet();
  final declared = <String>{};

  Finding finding(String message, Location location) => Finding(
    rule: lockfileOutOfSyncRule,
    severity: Severity.error,
    message: message,
    location: location,
  );

  for (final dependency in pubspec.dependencies(includeDev: true)) {
    declared.add(dependency.name);
    if (overridden.contains(dependency.name)) continue;
    final location = dependency.entry.keyLocation;
    final locked = lock.packages[dependency.name];
    if (locked == null) {
      findings.add(
        finding('"${dependency.name}" is missing from pubspec.lock.', location),
      );
      continue;
    }
    final source = _declaredSource(dependency);
    if (locked.source != source) {
      findings.add(
        finding(
          'pubspec.lock resolves "${dependency.name}" from ${locked.source}, '
          'but pubspec.yaml declares $source.',
          location,
        ),
      );
      continue;
    }
    if (source != 'hosted') continue;
    final constraintText = _constraintText(dependency);
    if (constraintText == null) continue;
    try {
      final constraint = VersionConstraint.parse(constraintText);
      if (!constraint.allows(Version.parse(locked.version))) {
        findings.add(
          finding(
            'pubspec.lock does not satisfy "${dependency.name}": locked '
            '${locked.version}, required $constraintText.',
            location,
          ),
        );
      }
    } on FormatException {
      // Not a constraint or a version: pub itself will say so.
      continue;
    }
  }

  for (final MapEntry(key: name, value: locked) in lock.packages.entries) {
    final direct =
        locked.dependencyKind == 'direct main' ||
        locked.dependencyKind == 'direct dev';
    if (direct && !declared.contains(name)) {
      findings.add(
        finding(
          'pubspec.lock lists "$name" as a direct dependency, but '
          'pubspec.yaml does not declare it.',
          Location.wholeFile(pubspecPath),
        ),
      );
    }
  }
  return findings;
}

/// `git`, `path`, `sdk` or `hosted`, which is also what a plain version
/// constraint means.
String _declaredSource(DependencyEntry dependency) {
  for (final source in const ['git', 'path', 'sdk']) {
    if (dependency.field(source) != null) return source;
  }
  return 'hosted';
}

/// The version constraint of a hosted dependency as written, or null when
/// there is none or it allows everything.
String? _constraintText(DependencyEntry dependency) {
  final node = switch (dependency.entry.value) {
    LocatedMap(:final entries) => entries['version']?.value,
    final other => other,
  };
  if (node case LocatedScalar(value: final String text)) {
    final trimmed = text.trim();
    if (trimmed.isNotEmpty && trimmed != 'any') return trimmed;
  }
  return null;
}

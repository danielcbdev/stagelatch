/// The `pubspec/path-dependency` rule.
library;

import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The name of the manifest every Dart package has at its root.
const String pubspecFileName = 'pubspec.yaml';

/// A Windows drive prefix, such as `C:`. Anchored and of fixed length, so
/// matching is constant time (security rule S6).
final _drivePrefix = RegExp('^[A-Za-z]:');

/// Reports dependencies of [document] whose `path` does not lead to a
/// package of this repository.
///
/// A path dependency between packages of the same repository works for
/// everyone who clones it, so it is allowed. What is reported is a path
/// that only exists on one machine: one that leaves the repository, or
/// that points at a directory with no committed `pubspec.yaml`.
///
/// [pubspecPath] is where [document] lives and [pubspecsInSnapshot] is
/// every `pubspec.yaml` of the snapshot. `dependency_overrides` are not
/// looked at; they have their own rule.
List<Finding> pathDependencyFindings(
  PubspecDocument document,
  RepoPath pubspecPath,
  Set<RepoPath> pubspecsInSnapshot,
) => [
  for (final dependency in document.dependencies(includeDev: true))
    // Only a string is a path. Anything else is malformed for pub itself.
    if (dependency.field('path')?.value case LocatedScalar(
      value: final String path,
      :final location,
    ))
      if (!pubspecsInSnapshot.contains(targetPubspec(pubspecPath, path)))
        Finding(
          rule: pathDependencyRule,
          severity: Severity.error,
          message:
              'Dependency "${dependency.name}" uses a path that is not a '
              'package in this repository: $path.',
          location: location,
        ),
];

/// The `pubspec.yaml` a path dependency points at, or null when
/// [dependencyPath] leaves the repository.
///
/// [dependencyPath] is resolved against the directory of [pubspecPath], as
/// pub does. It leaves the repository when it is empty, absolute, starts
/// with a drive letter or `~`, or climbs above the root. This is plain
/// text arithmetic on purpose: a check never touches the file system.
RepoPath? targetPubspec(RepoPath pubspecPath, String dependencyPath) {
  // pub accepts both separators in a path dependency.
  final path = dependencyPath.replaceAll(r'\', '/');
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.startsWith('~') ||
      _drivePrefix.hasMatch(path)) {
    return null;
  }
  final segments = [...?pubspecPath.parent?.value.split('/')];
  for (final segment in path.split('/')) {
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (segments.isEmpty) return null;
        segments.removeLast();
      default:
        segments.add(segment);
    }
  }
  return RepoPath([...segments, pubspecFileName].join('/'));
}

/// The `pubspec/unpinned-git` rule.
library;

import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// A full commit id: exactly 40 hexadecimal characters. Anchored and of
/// fixed length, so matching is constant time (security rule S6).
final _commitId = RegExp(r'^[0-9a-fA-F]{40}$');

/// Reports git dependencies of [document] that are not pinned.
///
/// A git dependency without a `ref` follows the default branch, so two
/// people resolving it on different days get different code. With
/// [requireSha] a `ref` must also be a full commit id, because a branch or
/// a tag can move.
///
/// `dependency_overrides` are not looked at; they have their own rule.
/// [pubspecPath] is where [document] lives, for the locations.
List<Finding> unpinnedGitFindings(
  PubspecDocument document,
  RepoPath pubspecPath, {
  required bool requireSha,
}) {
  final findings = <Finding>[];
  for (final dependency in document.dependencies(includeDev: true)) {
    final git = dependency.field('git');
    if (git == null) continue;

    // The short form, `git: <url>`, has no room for a ref.
    final ref = switch (git.value) {
      LocatedMap(:final entries) => entries['ref']?.value,
      _ => null,
    };
    final text = switch (ref) {
      LocatedScalar(:final value?) when '$value'.isNotEmpty => '$value',
      _ => null,
    };
    if (ref == null || text == null) {
      findings.add(
        Finding(
          rule: unpinnedGitRule,
          severity: Severity.error,
          message: 'Git dependency "${dependency.name}" has no ref.',
          location: git.keyLocation,
        ),
      );
    } else if (requireSha && !_commitId.hasMatch(text)) {
      findings.add(
        Finding(
          rule: unpinnedGitRule,
          severity: Severity.error,
          message:
              'Git dependency "${dependency.name}" must be pinned to a full '
              'commit SHA, found "$text".',
          location: ref.location,
        ),
      );
    }
  }
  return findings;
}

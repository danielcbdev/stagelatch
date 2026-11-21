/// One entry under `custom_checks:` (docs/specs/custom-checks.md §5).
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// A configured out-of-process check.
@immutable
final class CustomCheckConfig {
  /// Creates a validated entry. [sources] is non-empty (explicit or inferred).
  const new({
    required this.id,
    required this.run,
    required this.timeout,
    required this.sources,
    required this.rules,
    required this.settings,
  });

  /// The check id: the map key under `custom_checks:`.
  final String id;

  /// Executable and arguments. Never a shell string.
  final List<String> run;

  /// Wall-clock budget for the child. Default 60s.
  final Duration timeout;

  /// Source closure paths: explicit, or the single inferred entry.
  final List<RepoPath> sources;

  /// Severity overrides keyed by the local rule name (no check prefix).
  final Map<String, RuleLevel> rules;

  /// Extra keys from the entry, sent on protocol `init`.
  final Map<String, Object?> settings;
}

/// The repository-relative entry path inferred from [run], or null when
/// inference cannot produce one without a snapshot
/// (docs/specs/custom-checks.md §6).
RepoPath? inferCustomCheckSourceEntry(List<String> run) {
  if (run.isEmpty) return null;
  final first = run.first;
  if (first == 'dart' || first == 'flutter') {
    for (final argument in run.skip(1)) {
      if (!argument.endsWith('.dart')) continue;
      // package: URIs end in .dart but are not repository paths.
      if (argument.contains(':')) continue;
      try {
        return RepoPath(argument);
      } on FormatException {
        // Not a clean repository-relative path.
      }
    }
    return null;
  }
  try {
    final path = RepoPath(first);
    // A single segment with no '.' is a bare command (python, node), not a
    // repository file. Without a snapshot we cannot tell them apart, so
    // inference fails and config must set sources (custom-checks.md §6).
    if (!first.contains('/') && !first.contains('.')) {
      return null;
    }
    return path;
  } on FormatException {
    return null;
  }
}

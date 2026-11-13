/// The validated configuration of a repository.
library;

import 'package:glob/glob.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/hook_selector.dart';
import 'package:stagelatch/src/application/config/settings.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Everything `stagelatch.yaml` can say, with defaults filled in
/// (docs/specs/config.md).
///
/// An instance is always complete and valid: the loader either produces
/// one or throws. Globs, sizes and durations are already parsed.
final class Config {
  /// Creates a configuration. Used by the loader.
  const new({
    required this.minVersion,
    required this.hooks,
    required this.rules,
    required this.exclude,
    required this.sdkPath,
    required this.timeBudget,
    required this.baselinePath,
    required this.format,
    required this.analyze,
    required this.codegen,
    required this.pubspec,
    required this.assets,
    required this.tests,
  });

  /// The oldest tool version the repository accepts, or null.
  final Version? minVersion;

  /// What each hook runs. Always has the keys `pre-commit`, `pre-push`
  /// and `ci`.
  final Map<String, List<HookSelector>> hooks;

  /// Severity overrides by rule (ADR-0009).
  final Map<RuleId, RuleLevel> rules;

  /// Paths that never produce findings.
  final List<Glob> exclude;

  /// Where the Dart or Flutter SDK is, when the repository says so.
  final String? sdkPath;

  /// How long a run may take before a notice is printed. Never changes
  /// what runs (ADR-0003).
  final Duration timeBudget;

  /// Where the baseline file is.
  final RepoPath baselinePath;

  /// Parameters of the `format` check.
  final FormatSettings format;

  /// Parameters of the `analyze` check.
  final AnalyzeSettings analyze;

  /// Parameters of the `codegen` check.
  final CodegenSettings codegen;

  /// Parameters of the `pubspec` check.
  final PubspecSettings pubspec;

  /// Parameters of the `assets` check.
  final AssetsSettings assets;

  /// Parameters of the `tests` check.
  final TestsSettings tests;

  /// The settings object of type [T], for example `AssetsSettings`.
  ///
  /// Throws [StateError] when no check has settings of that type.
  T settings<T extends Object>() {
    for (final candidate in [
      format,
      analyze,
      codegen,
      pubspec,
      assets,
      tests,
    ]) {
      if (candidate is T) return candidate;
    }
    throw StateError('No check has settings of type $T.');
  }
}

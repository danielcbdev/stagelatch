/// The parameters of the `pubspec` check (docs/specs/config.md, section 3).
library;

import 'package:stagelatch/src/domain/text_predicate.dart';

/// Parameters of the `pubspec` check.
final class PubspecSettings {
  /// Creates the settings.
  const new({this.monotonicBuildNumber = const [], this.requireSha = false});

  /// One predicate per glob of `pubspec.monotonic_build_number`, each
  /// answering whether a branch name matches it.
  final List<TextPredicate> monotonicBuildNumber;

  /// Whether a git dependency must be pinned to a full commit id.
  final bool requireSha;

  /// Whether `pubspec/build-number-regression` applies to [branch].
  bool buildNumberMustGrowOn(String branch) =>
      monotonicBuildNumber.any((matches) => matches(branch));
}

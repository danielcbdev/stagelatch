/// The parameters of the `assets` check (docs/specs/config.md, section 3).
library;

import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/text_predicate.dart';

/// Parameters of the `assets` check.
///
/// [roots] and [ignore] are read relative to each package: in a package at
/// `packages/ui`, the root `assets` is `packages/ui/assets`.
final class AssetsSettings {
  /// Creates the settings. [roots] defaults to the `assets` directory.
  new({
    this.maxFileSize = 500 * 1024,
    List<RepoPath>? roots,
    this.ignore = const [],
  }) : roots = roots ?? [RepoPath('assets')];

  /// The largest allowed asset, in bytes.
  final int maxFileSize;

  /// The directories whose files are expected to be declared assets.
  final List<RepoPath> roots;

  /// One predicate per glob of `assets.ignore`, each answering whether a
  /// path relative to the package matches it. Every `assets` rule leaves a
  /// matching path alone.
  final List<TextPredicate> ignore;
}

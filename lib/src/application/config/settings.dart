/// The typed parameters of each check (docs/specs/config.md, section 3).
library;

import 'package:glob/glob.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// Parameters of the `format` check.
final class FormatSettings {
  /// Creates the settings.
  const new({this.fix = true});

  /// Whether formatting is written to the index on pre-commit.
  final bool fix;
}

/// Which files `analyze` looks at.
enum AnalyzeScope {
  /// Only the changed Dart files.
  changed,

  /// The changed Dart files and everything that imports them.
  affected,

  /// Every Dart file of each package that has a changed file.
  all,
}

/// Parameters of the `analyze` check.
final class AnalyzeSettings {
  /// Creates the settings.
  const new({
    this.scope = AnalyzeScope.affected,
    this.failOn = const {DiagnosticSeverity.error, DiagnosticSeverity.warning},
  });

  /// Which files are analyzed.
  final AnalyzeScope scope;

  /// The analyzer severities that block.
  final Set<DiagnosticSeverity> failOn;
}

/// Parameters of the `codegen` check.
final class CodegenSettings {
  /// Creates the settings.
  const new({
    this.generatedFilesCommitted = true,
    this.generatedSuffixes = const ['.g.dart', '.freezed.dart'],
  });

  /// Whether the repository commits generated files. When false,
  /// `codegen/stale` has nothing to compare and is disabled.
  final bool generatedFilesCommitted;

  /// File name suffixes that mark a generated part file.
  final List<String> generatedSuffixes;
}

/// Parameters of the `pubspec` check.
final class PubspecSettings {
  /// Creates the settings.
  const new({this.monotonicBuildNumber = const [], this.requireSha = false});

  /// Branches on which `pubspec/build-number-regression` applies.
  final List<Glob> monotonicBuildNumber;

  /// Whether a git dependency must be pinned to a full commit id.
  final bool requireSha;
}

/// Parameters of the `assets` check.
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

  /// Asset paths that every `assets` rule leaves alone.
  final List<Glob> ignore;
}

/// Parameters of the `tests` check.
final class TestsSettings {
  /// Creates the settings.
  const new({this.functions = const ['test', 'testWidgets', 'group']});

  /// The functions whose calls count as tests or groups.
  final List<String> functions;
}

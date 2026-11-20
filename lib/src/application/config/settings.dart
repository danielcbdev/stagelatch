/// The typed parameters of each check (docs/specs/config.md, section 3).
library;

export 'package:stagelatch/src/checks/analyze/analyze_settings.dart';
export 'package:stagelatch/src/checks/assets/assets_settings.dart';
export 'package:stagelatch/src/checks/format/format_settings.dart';
export 'package:stagelatch/src/checks/pubspec/pubspec_settings.dart';

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

/// Parameters of the `tests` check.
final class TestsSettings {
  /// Creates the settings.
  const new({this.functions = const ['test', 'testWidgets', 'group']});

  /// The functions whose calls count as tests or groups.
  final List<String> functions;
}

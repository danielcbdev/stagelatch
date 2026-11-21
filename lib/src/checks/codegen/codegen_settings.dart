/// The parameters of the `codegen` check (docs/specs/config.md, section 3).
library;

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

/// The parameters of the `format` check (docs/specs/config.md, section 3).
library;

/// Parameters of the `format` check.
final class FormatSettings {
  /// Creates the settings.
  const new({this.fix = true});

  /// Whether formatting is written to the index on pre-commit.
  final bool fix;
}

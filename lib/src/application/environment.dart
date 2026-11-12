/// The process environment, captured once as a value.
library;

/// Everything the tool needs to know about the process it runs in.
///
/// It is built once, in the composition root, and passed down. Nothing else
/// reads environment variables, the working directory or terminal state,
/// which keeps every other class testable and deterministic (ADR-0003).
final class Environment {
  /// Captures the environment. [variables] is copied.
  new({
    required this.workingDirectory,
    required Map<String, String> variables,
    required this.stdoutIsTerminal,
    required this.stdinIsTerminal,
    this.colorOverride,
  }) : variables = Map.unmodifiable(variables);

  /// The directory the tool acts in: the current directory, or the value of
  /// `--directory`.
  final String workingDirectory;

  /// The environment variables. Unmodifiable. Their values are never
  /// printed (security rule S5).
  final Map<String, String> variables;

  /// Whether standard output is a terminal.
  final bool stdoutIsTerminal;

  /// Whether standard input is a terminal.
  final bool stdinIsTerminal;

  /// The value of `--color` or `--no-color`, or null when neither was given.
  final bool? colorOverride;

  /// Whether output may contain color escape sequences (ADR-0011).
  ///
  /// An explicit [colorOverride] wins. Otherwise color needs a terminal and
  /// no `NO_COLOR`; an empty `NO_COLOR` does not count, as the convention at
  /// no-color.org specifies.
  bool get useColor =>
      colorOverride ??
      (stdoutIsTerminal && (variables['NO_COLOR'] ?? '').isEmpty);
}

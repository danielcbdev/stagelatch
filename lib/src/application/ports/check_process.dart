/// How the host talks to a custom-check child process
/// (docs/specs/custom-checks.md sections 7–11).
library;

/// A running custom-check child: line-oriented stdin/stdout plus lifecycle.
abstract interface class CheckProcess {
  /// Stdout lines from the child (no trailing newlines).
  Stream<String> get lines;

  /// Writes one protocol line to the child's stdin (appends the newline).
  void send(String line);

  /// Closes the child's stdin after the host is done sending.
  Future<void> closeStdin();

  /// Stops the child and waits until it has exited.
  Future<void> kill();

  /// The child's exit code, once it has exited.
  Future<int> get exitCode;

  /// The first 64 KiB of stderr, completed when the stderr stream ends.
  Future<String> get standardError;
}

/// Starts custom-check children.
abstract interface class CheckProcessFactory {
  /// Starts [command] with [workingDirectory] as the repository root.
  ///
  /// Never uses a shell. Resolves bare `run[0]` names and `dart`/`flutter`
  /// before spawn when the concrete factory is configured to do so.
  Future<CheckProcess> start(
    List<String> command, {
    required String workingDirectory,
  });
}

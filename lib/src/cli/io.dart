/// The streams and environment a command run sees.
library;

import 'package:stagelatch/src/application/environment.dart';

/// Where a command reads and writes, captured once.
///
/// Tests pass buffers and a fixed [environment]. The executable passes
/// the real standard streams.
final class Io {
  /// Creates the boundary for one invocation.
  const new({
    required this.stdout,
    required this.stderr,
    required this.stdin,
    required this.environment,
  });

  /// Reports and ordinary output.
  final StringSink stdout;

  /// Errors about the invocation, and `--verbose` diagnostics.
  final StringSink stderr;

  /// Standard input, for the pre-push hook.
  final Stream<List<int>> stdin;

  /// The process environment, including the working directory.
  final Environment environment;
}

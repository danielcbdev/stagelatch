/// One line of `doctor` (docs/specs/cli.md, section 3.6).
library;

import 'package:stagelatch/src/application/text/sanitize.dart';

/// How a probe went.
enum ProbeStatus {
  /// Nothing to do.
  ok,

  /// Worth a look, but nothing is broken.
  warn,

  /// Broken; `doctor` exits 1.
  fail,
}

/// The outcome of one probe.
final class ProbeResult {
  /// Creates a result.
  const new(this.id, this.status, this.message);

  /// `D1` to `D9`.
  final String id;

  /// How it went.
  final ProbeStatus status;

  /// What it found, unsanitized.
  final String message;

  /// The console line: the status padded to six characters, the id, one
  /// space, the message with control characters removed (S5).
  String toConsoleLine() =>
      '${status.name.padRight(6)}$id ${sanitizeForTerminal(message)}';
}

/// 1 when any probe failed, else 0.
int doctorExitCode(List<ProbeResult> results) =>
    results.any((result) => result.status == ProbeStatus.fail) ? 1 : 0;

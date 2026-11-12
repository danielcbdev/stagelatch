/// The port through which checks obtain Dart diagnostics, formatting and
/// syntactic facts.
library;

import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// The severity the analyzer assigns to a diagnostic.
enum DiagnosticSeverity {
  /// A compile-time error.
  error,

  /// A warning.
  warning,

  /// An informational diagnostic, such as most lints.
  info,
}

/// One diagnostic, as `dart analyze` of the project's SDK would report it.
final class DartDiagnostic {
  /// Creates a diagnostic.
  const new({
    required this.location,
    required this.code,
    required this.severity,
    required this.message,
    this.correction,
  });

  /// The range the analyzer reports.
  final Location location;

  /// The analyzer's diagnostic code, for example `unused_import`.
  final String code;

  /// The analyzer's severity, before `analyze.fail_on` is applied.
  final DiagnosticSeverity severity;

  /// The analyzer's message.
  final String message;

  /// The analyzer's suggested correction, when it has one.
  final String? correction;
}

/// The result of formatting one file.
sealed class FormatOutcome {
  const new();
}

/// The file was formatted; [text] equals the input when nothing changed.
final class Formatted extends FormatOutcome {
  /// Creates the outcome.
  const new(this.text);

  /// What `dart format` of the project's SDK would write for the file.
  final String text;
}

/// The source does not parse, so it cannot be formatted. `analyze` reports
/// the syntax error.
final class Unparseable extends FormatOutcome {
  /// Creates the outcome.
  const new();
}

/// Everything Dart-specific a check may ask for.
///
/// How the answers are produced is hidden behind this interface on purpose:
/// the mechanism is chosen by the spike and may change (ADR-0008). Results
/// must equal those of the project SDK's `dart analyze` and `dart format`
/// on a working tree identical to the snapshot.
abstract interface class DartToolchain {
  /// The diagnostics of exactly [files], sorted by path, position and code.
  Future<List<DartDiagnostic>> diagnose(Set<RepoPath> files);

  /// Formats [source], the content of [path], with the project's settings.
  Future<FormatOutcome> format(RepoPath path, String source);

  /// The syntactic facts of [path] in [files], or null when the file is
  /// absent or does not parse. Never starts the expensive part of the
  /// toolchain.
  Future<DartFileFacts?> facts(SnapshotFiles files, RepoPath path);

  /// Releases every resource, including child processes.
  Future<void> close();
}

/// The ways a run can fail other than by reporting findings.
library;

import 'package:stagelatch/src/domain/location.dart';

/// A failure of the tool itself, as opposed to a problem in user content.
///
/// Problems in the files being judged are findings, never exceptions. This
/// hierarchy covers everything else, and each subtype maps to exactly one
/// exit code. It is sealed so that the mapping is checked by the compiler.
sealed class StagelatchException implements Exception {
  const new(this.message);

  /// What happened, as one or more complete sentences for the user.
  final String message;

  @override
  String toString() => message;
}

/// The tool was invoked in a way it cannot serve: bad arguments, not a git
/// work tree, a shallow clone without a merge base. Exit code 64.
final class UsageException extends StagelatchException {
  /// Creates the failure.
  const new(super.message);
}

/// `stagelatch.yaml` or the baseline file is invalid, or the tool is older
/// than the configured `min_version`. Exit code 78.
final class ConfigException extends StagelatchException {
  /// Creates the failure, pointing at [location] when the problem has one.
  const new(super.message, {this.location});

  /// Where in the file the problem is, or null when it concerns the file as
  /// a whole.
  final Location? location;

  /// `<file>:<line>:<column>: <message>`, or just the message without a
  /// location.
  @override
  String toString() => location == null ? message : '$location: $message';
}

/// Something unexpected: a bug, or a git command that failed where it
/// should not. Exit code 70.
final class InternalException extends StagelatchException {
  /// Creates the failure.
  const new(super.message, {this.where, this.cause, this.stackTrace});

  /// What was running, for example `check "pubspec"`; null when unknown.
  final String? where;

  /// The original error, when this wraps one.
  final Object? cause;

  /// The stack trace of [cause], printed only with `--verbose`.
  final StackTrace? stackTrace;
}

/// The exit codes of the `stagelatch` executable.
library;

import 'package:stagelatch/src/application/errors.dart';

/// Every exit code the tool uses (docs/specs/cli.md, section 2).
///
/// The values 64, 70 and 78 follow the BSD `sysexits` conventions for
/// usage, internal software and configuration errors.
enum ExitCode {
  /// No blocking finding, or the command succeeded.
  pass(0),

  /// At least one finding with severity error.
  findings(1),

  /// The tool was invoked incorrectly.
  usage(64),

  /// An unexpected failure.
  internal(70),

  /// Invalid configuration.
  config(78);

  new(this.code);

  /// The number handed to the operating system.
  final int code;

  /// The exit code for a failed run.
  static ExitCode forException(StagelatchException exception) =>
      switch (exception) {
        UsageException() => usage,
        ConfigException() => config,
        InternalException() => internal,
      };
}

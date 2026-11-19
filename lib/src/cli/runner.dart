/// Parses arguments and turns failures into exit codes.
library;

import 'package:args/command_runner.dart' as args;
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/cli/commands/init_command.dart';
import 'package:stagelatch/src/cli/commands/install_command.dart';
import 'package:stagelatch/src/cli/commands/run_command.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/exit_codes.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/version.dart';

/// Runs one invocation and returns the process exit code.
///
/// This is the only place, besides the pipeline, that catches every error.
/// [open] replaces [Composition.create] in tests.
Future<int> runStagelatch(
  List<String> arguments,
  Io io, {
  Future<Composition> Function(Io io)? open,
}) async {
  if (arguments.contains('--version')) {
    io.stdout.writeln('stagelatch $packageVersion');
    return ExitCode.pass.code;
  }
  final compose = open ?? Composition.create;
  final runner =
      args.CommandRunner<int>(
          'stagelatch',
          'Change-aware quality gate for Dart and Flutter repositories.',
        )
        ..argParser.addOption(
          'directory',
          abbr: 'C',
          help: 'Run in this directory.',
        )
        ..argParser.addFlag('color', help: 'Color the console report.')
        ..argParser.addFlag(
          'verbose',
          negatable: false,
          help: 'Print diagnostics.',
        )
        ..addCommand(InitCommand(io, compose))
        ..addCommand(InstallCommand(io, compose))
        ..addCommand(UninstallCommand(io, compose))
        ..addCommand(RunCommand(io, compose));
  try {
    return await runner.run(arguments) ?? ExitCode.pass.code;
  } on StagelatchException catch (error) {
    _writeFailure(
      io,
      error,
      bypass: _isRun(arguments),
      verbose: _verbose(arguments),
    );
    return ExitCode.forException(error).code;
  } on args.UsageException catch (error) {
    io.stderr.writeln(error.message);
    return ExitCode.usage.code;
  } on Object catch (error, stackTrace) {
    _writeInternal(
      io,
      where: 'command',
      message: error.toString(),
      stackTrace: _verbose(arguments) ? stackTrace : null,
      bypass: _isRun(arguments),
    );
    return ExitCode.internal.code;
  }
}

void _writeFailure(
  Io io,
  StagelatchException error, {
  required bool bypass,
  required bool verbose,
}) {
  switch (error) {
    case InternalException():
      _writeInternal(
        io,
        where: error.where ?? 'command',
        message: error.message,
        stackTrace: verbose ? error.stackTrace : null,
        bypass: bypass,
      );
    case ConfigException():
      io.stderr.writeln(error.toString());
    case UsageException():
      io.stderr.writeln(error.message);
  }
}

void _writeInternal(
  Io io, {
  required String where,
  required String message,
  required StackTrace? stackTrace,
  required bool bypass,
}) {
  io.stderr.writeln('stagelatch: internal error in $where: $message');
  io.stderr.writeln('This is a bug in stagelatch, not in your change.');
  if (bypass) {
    io.stderr.writeln('To proceed anyway: git commit --no-verify');
  }
  io.stderr.writeln(
    'Report it: https://github.com/danielcbdev/stagelatch/issues',
  );
  if (stackTrace != null) io.stderr.writeln(stackTrace);
}

bool _verbose(List<String> arguments) => arguments.contains('--verbose');

bool _isRun(List<String> arguments) {
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--directory' || argument == '-C') {
      i += 1;
      continue;
    }
    if (argument.startsWith('-')) continue;
    return argument == 'run';
  }
  return false;
}

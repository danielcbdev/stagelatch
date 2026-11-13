/// Applies `-C` and `--color` to the environment a command sees.
library;

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/cli/io.dart';

/// The [io] a [command] should use, after global options.
Io scopeCommand(Command<int> command, Io io) {
  final global = command.globalResults;
  if (global == null) return io;
  final directory = global.option('directory');
  final workingDirectory = directory == null
      ? io.environment.workingDirectory
      : p.normalize(
          p.isAbsolute(directory)
              ? directory
              : p.join(io.environment.workingDirectory, directory),
        );
  return Io(
    stdout: io.stdout,
    stderr: io.stderr,
    stdin: io.stdin,
    environment: Environment(
      workingDirectory: workingDirectory,
      variables: io.environment.variables,
      stdoutIsTerminal: io.environment.stdoutIsTerminal,
      stdinIsTerminal: io.environment.stdinIsTerminal,
      colorOverride: global.wasParsed('color')
          ? global.flag('color')
          : io.environment.colorOverride,
    ),
  );
}

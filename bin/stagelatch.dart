import 'dart:io';

import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/runner.dart';

/// Entry point of the `stagelatch` executable.
///
/// Builds [Io] from the process and leaves [exitCode] set to the result.
/// It does not call `exit`, so a test can invoke the same runner in-process.
Future<void> main(List<String> arguments) async {
  final io = Io(
    stdout: stdout,
    stderr: stderr,
    stdin: stdin,
    environment: Environment(
      workingDirectory: Directory.current.path,
      variables: Platform.environment,
      stdoutIsTerminal: stdout.hasTerminal,
      stdinIsTerminal: stdin.hasTerminal,
    ),
  );
  exitCode = await runStagelatch(arguments, io);
}

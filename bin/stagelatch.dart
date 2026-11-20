import 'dart:convert';
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
    stdin: _standardInput(),
    environment: Environment(
      workingDirectory: Directory.current.path,
      variables: Platform.environment,
      stdoutIsTerminal: stdout.hasTerminal,
      stdinIsTerminal: stdin.hasTerminal,
    ),
  );
  exitCode = await runStagelatch(arguments, io);
}

/// Standard input, read lazily and synchronously.
///
/// Not `stdin` as a stream: that closes descriptor 0 at end of input, and on
/// Dart 3.14.1 for macOS a pipe created afterwards for a child process
/// (`git cat-file`) then ends up with its standard input closed, so the
/// child exits at once. pre-push reads git's input to its end and starts
/// git processes afterwards. Synchronous reads leave the descriptor open.
Stream<List<int>> _standardInput() async* {
  while (true) {
    final line = stdin.readLineSync(encoding: utf8, retainNewlines: true);
    if (line == null) return;
    yield utf8.encode(line);
  }
}

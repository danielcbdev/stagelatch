/// Runs external processes with a fixed argument list and fails loudly.
library;

import 'dart:convert';
import 'dart:io';

/// Runs [executable] with [arguments] and returns its stdout.
///
/// Throws a [ProcessException] carrying stderr when the exit code is not
/// zero. [stdin] is written and closed before waiting, for `git apply` and
/// `git hash-object --stdin`.
Future<String> run(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  String? stdin,
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  if (stdin != null) process.stdin.write(stdin);
  await process.stdin.close();
  final code = await process.exitCode;
  final output = await out;
  if (code != 0) {
    throw ProcessException(executable, arguments, await err, code);
  }
  return output;
}

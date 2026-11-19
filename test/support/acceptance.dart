/// Shared setup for the acceptance scenarios.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'temp_repo.dart';

/// A pubspec with no findings.
const cleanPubspec = 'name: app\n';

/// A pubspec whose path dependency leaves the repository.
const badPubspec =
    'name: app\ndependencies:\n  design_system:\n    path: ../x\n';

/// Replaces durations so two runs can be compared.
///
/// Durations are the only part of a report that depends on the machine
/// (ADR-0003).
String stabilize(String text) => text
    .replaceAll(RegExp(r'\b\d+ms\b'), 'Nms')
    .replaceAll(RegExp(r'\b\d+\.\ds\b'), 'N.Ns');

/// The console report for one clean pre-commit of [files] changed paths.
String cleanReport(int files) {
  final counted = files == 1 ? '1 file' : '$files files';
  return 'stagelatch pre-commit: $counted\n'
      '\n'
      '  pubspec  ok  Nms\n'
      '\n'
      '0 errors, 0 warnings. Commit allowed. (N.Ns)\n';
}

/// The console report for one blocking path dependency in `pubspec.yaml`.
String blockedReport(int files) {
  final counted = files == 1 ? '1 file' : '$files files';
  return 'stagelatch pre-commit: $counted\n'
      '\n'
      '  pubspec  1 error  Nms\n'
      '\n'
      'pubspec.yaml:4:11  error  pubspec/path-dependency\n'
      '  Dependency "design_system" uses a path that is not a package in '
      'this repository: ../x.\n'
      '\n'
      '1 error, 0 warnings. Commit blocked. (N.Ns)\n';
}

/// Asserts the exit code and the whole report, durations aside.
void expectRun(
  CliResult result, {
  required int exitCode,
  required String stdout,
}) {
  expect(result.exitCode, exitCode, reason: result.stderr);
  expect(stabilize(result.stdout), stdout);
  expect(result.stdout, isNot(contains('\u001b')));
}

/// Runs git and keeps both streams. Does not throw on a non-zero exit.
Future<({int code, String stdout, String stderr})> runGit(
  TempRepo repo,
  List<String> args, {
  String? workingDirectory,
  Map<String, String> env = const {},
}) async {
  final process = await Process.start(
    'git',
    args,
    workingDirectory: workingDirectory ?? repo.root,
    environment: {...repo.environment, ...env},
    includeParentEnvironment: false,
  );
  await process.stdin.close();
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;
  return (code: code, stdout: await stdout, stderr: await stderr);
}

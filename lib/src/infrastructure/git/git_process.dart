/// The single place where the git executable is started.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/infrastructure/git/git_result.dart';

/// Starts git in one repository.
///
/// Security rule S1: git is started with an executable and an argument
/// list, never through a shell, so no argument is ever interpreted.
///
/// Security rule S11: git receives exactly the environment given here,
/// which the composition root captures from the parent process unchanged.
/// That is how `GIT_INDEX_FILE`, `GIT_DIR` and `GIT_WORK_TREE`, which git
/// sets while running a hook, reach the commands we run.
final class GitProcess {
  /// Creates a launcher for the repository at [workingDirectory].
  ///
  /// [executable] exists for tests; production code uses the default.
  new({
    required this.workingDirectory,
    required Map<String, String> environment,
    this.executable = 'git',
  }) : _environment = Map.unmodifiable(environment);

  /// The directory git runs in.
  final String workingDirectory;

  /// The program to start.
  final String executable;

  final Map<String, String> _environment;

  /// Runs `git <args>` to completion.
  ///
  /// [stdin], when given, is written to git's standard input, which is
  /// then closed. It is closed in every case, so git can never wait for
  /// input that will not come (ADR-0011).
  ///
  /// Throws [InternalException], with the command and git's error output,
  /// when the exit code is not in [okExitCodes]. Throws [UsageException]
  /// when git cannot be started at all.
  Future<GitResult> run(
    List<String> args, {
    List<int>? stdin,
    Set<int> okExitCodes = const {0},
  }) async {
    final process = await start(args);
    // Listen to both pipes before waiting for the exit code: a process
    // that fills an unread pipe blocks forever.
    final stdout = process.stdout.fold(
      BytesBuilder(copy: false),
      (builder, chunk) => builder..add(chunk),
    );
    final stderr = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    try {
      if (stdin != null) process.stdin.add(stdin);
      await process.stdin.close();
    } on IOException {
      // git exited before reading its input. The exit code below says why.
    }
    final exitCode = await process.exitCode;
    final result = GitResult(
      exitCode: exitCode,
      stdout: (await stdout).takeBytes(),
      stderr: await stderr,
    );
    if (!okExitCodes.contains(exitCode)) {
      throw InternalException(
        'git ${args.join(' ')} exited with $exitCode: '
        '${result.stderr.trim()}',
        where: 'git',
      );
    }
    return result;
  }

  /// Starts `git <args>` and hands the running process to the caller, who
  /// owns its pipes and must see it end.
  ///
  /// Throws [UsageException] when git cannot be started.
  Future<Process> start(List<String> args) async {
    try {
      return await Process.start(
        executable,
        args,
        workingDirectory: workingDirectory,
        environment: _environment,
        // The environment was captured whole by the caller; adding the
        // parent's again would hide what git really receives.
        includeParentEnvironment: false,
      );
    } on ProcessException {
      throw const UsageException(
        'Could not run git. Is it installed and on PATH?',
      );
    }
  }
}

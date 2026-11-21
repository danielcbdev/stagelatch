/// Runs test files with the resolved SDK's `dart test` or `flutter test`
/// (ADR-0018, docs/specs/dart-toolchain.md, section 9, security S14).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/application/ports/test_runner_factory.dart';
import 'package:stagelatch/src/domain/dart/test_runner.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/test_command.dart';
import 'package:stagelatch/src/infrastructure/dart/test_event_parser.dart';

/// The shape of [Process.start]; tests replace it to inspect the command and
/// to play back canned output.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
  ProcessStartMode mode,
});

/// How much of the tool's standard error is kept: the first 64 KiB.
const int _maxStandardError = 64 * 1024;

/// How long a killed child gets to exit before it is killed for good.
const _defaultKillGrace = Duration(seconds: 5);

/// How each stdout line is fed to the parser. Tests replace it to throw.
typedef TestLineConsumer = void Function(TestEventParser parser, String line);

/// Characters a Windows batch file (`.bat`, `.cmd`) would read as shell
/// syntax even in a quoted argument.
const _batchMetacharacters = '"&|<>^%!';

/// Starts `dart test` or `flutter test` for the files of one package.
///
/// Processes are started with an argument list and never through a shell,
/// with the environment inherited unchanged and standard input closed at
/// once. The output is read as a stream of lines, never buffered whole.
final class ProcessTestRunner implements TestRunner {
  /// Creates a runner that starts the tools of [sdk] in the working tree at
  /// [repoRoot].
  ///
  /// [starter] defaults to [Process.start]. [isWindows] defaults to the
  /// platform. [killGrace] is how long a killed child has to exit before
  /// SIGKILL; the default is 5 seconds. [consumeLine] feeds each stdout
  /// line to the parser; tests replace it to throw.
  new({
    required this.sdk,
    required this.repoRoot,
    ProcessStarter? starter,
    bool? isWindows,
    Duration? killGrace,
    TestLineConsumer? consumeLine,
  }) : _start = starter ?? Process.start,
       _isWindows = isWindows ?? Platform.isWindows,
       _killGrace = killGrace ?? _defaultKillGrace,
       _consumeLine = consumeLine ?? _addLine,
       _context = switch (isWindows) {
         null => p.context,
         true => p.windows,
         false => p.posix,
       };

  /// The SDK whose tools run the tests.
  final ResolvedSdk sdk;

  /// The repository root, as given.
  final String repoRoot;

  final ProcessStarter _start;
  final bool _isWindows;
  final Duration _killGrace;
  final TestLineConsumer _consumeLine;
  final p.Context _context;

  static void _addLine(TestEventParser parser, String line) => parser.add(line);

  /// The root with symlinks resolved, computed once: the tools report real
  /// paths, and on macOS a temporary directory is `/private/tmp/...`.
  Future<String>? _resolvedRoot;

  @override
  Future<TestRunResult> run(DartPackage package, List<RepoPath> files) async {
    if (files.isEmpty) return const TestRunResult();
    if (package.usesFlutter && sdk.flutterExecutable == null) {
      return const TestRunResult(
        startupError: 'the resolved SDK has no flutter executable',
      );
    }
    final commands = testCommands(sdk: sdk, package: package, files: files);
    final unsafe = _unsafePath(commands);
    if (unsafe != null) {
      return TestRunResult(startupError: 'unsafe test path: $unsafe');
    }
    final root = await (_resolvedRoot ??= _resolveRoot());
    final results = <TestRunResult>[];
    for (final command in commands) {
      results.add(await _runCommand(command, root));
    }
    return TestRunResult.merge(results);
  }

  Future<String> _resolveRoot() async {
    try {
      return await Directory(repoRoot).resolveSymbolicLinks();
    } on FileSystemException {
      return repoRoot;
    }
  }

  /// The first test path a batch file executable could not take safely, or
  /// null. Only Windows has batch files: there `flutter.bat` is run by
  /// `cmd.exe`, which reads metacharacters even in a quoted argument, so
  /// such a path is refused instead of passed (S14).
  String? _unsafePath(List<TestCommand> commands) {
    if (!_isWindows) return null;
    for (final command in commands) {
      final executable = command.executable.toLowerCase();
      if (!executable.endsWith('.bat') && !executable.endsWith('.cmd')) {
        continue;
      }
      for (final file in command.files) {
        if (file.codeUnits.any(_isUnsafeForBatch)) return file;
      }
    }
    return null;
  }

  static bool _isUnsafeForBatch(int unit) =>
      unit < 0x20 ||
      unit == 0x7f ||
      _batchMetacharacters.codeUnits.contains(unit);

  Future<TestRunResult> _runCommand(TestCommand command, String root) async {
    final directory = command.directory;
    final workingDirectory = directory == null
        ? root
        : _context.joinAll([root, ...directory.value.split('/')]);
    final first = command.files.first;
    final fallback = RepoPath(
      directory == null ? first : '${directory.value}/$first',
    );

    final Process process;
    try {
      process = await _start(
        command.executable,
        command.arguments,
        workingDirectory: workingDirectory,
        runInShell: false,
      );
    } on ProcessException catch (error) {
      return TestRunResult(
        startupError: 'cannot start ${command.executable}: ${error.message}',
      );
    }

    var exited = false;
    try {
      unawaited(_closeStdin(process));
      final standardError = _readStandardError(process.stderr);
      final parser = TestEventParser(
        repoRoot: root,
        fallbackFile: fallback,
        context: _context,
      );
      final lines = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());
      await lines.forEach((line) => _consumeLine(parser, line));
      final exitCode = await process.exitCode;
      exited = true;
      return parser.finish(
        exitCode: exitCode,
        standardError: await standardError,
      );
    } finally {
      if (!exited) await _kill(process);
    }
  }

  /// Closes the child's standard input; it is never written to. A child
  /// that has already gone is not an error.
  Future<void> _closeStdin(Process process) async {
    try {
      await process.stdin.close();
    } on IOException {
      // The child exited before reading its input: nothing to close.
    }
  }

  /// Reads at most the first [_maxStandardError] bytes of [stream] and
  /// keeps draining the rest, so a chatty child never blocks on a full pipe.
  Future<String> _readStandardError(Stream<List<int>> stream) {
    final kept = BytesBuilder(copy: false);
    final done = Completer<String>();
    stream.listen(
      (chunk) {
        final room = _maxStandardError - kept.length;
        if (room <= 0) return;
        kept.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
      },
      onError: (Object _) {},
      onDone: () =>
          done.complete(utf8.decode(kept.takeBytes(), allowMalformed: true)),
    );
    return done.future;
  }

  /// Stops [process] and waits until it has exited.
  ///
  /// SIGTERM first, then SIGKILL if it has not exited after [_killGrace].
  /// Grandchildren are not killed (docs/specs/dart-toolchain.md, section 9).
  Future<void> _kill(Process process) async {
    process.kill();
    try {
      await process.exitCode.timeout(_killGrace);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }
}

/// Creates [ProcessTestRunner]s.
final class ProcessTestRunnerFactory implements TestRunnerFactory {
  /// Creates the factory.
  const new();

  @override
  TestRunner create({required ResolvedSdk sdk, required String repoRoot}) =>
      ProcessTestRunner(sdk: sdk, repoRoot: repoRoot);
}

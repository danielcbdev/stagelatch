/// Spawns custom-check children with resolved executables
/// (docs/specs/custom-checks.md sections 7–8, ADR-0019).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/check_process.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/application/text/sanitize.dart';
import 'package:stagelatch/src/infrastructure/io/path_executable.dart';

/// The shape of `Process.start`; tests replace it.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
  ProcessStartMode mode,
});

/// How much of the child's stderr is kept.
const int maxCustomCheckStandardError = 64 * 1024;

const _defaultKillGrace = Duration(seconds: 5);

/// Characters a Windows batch file would read as shell syntax.
const _batchMetacharacters = '"&|<>^%!';

/// A [CheckProcess] backed by an OS process.
final class SpawnedCheckProcess implements CheckProcess {
  new _(this._process, {required this._killGrace}) {
    _lines = _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    _standardError = _readStandardError(_process.stderr);
    _active.add(this);
  }

  /// Children that have been started and not yet [kill]ed.
  ///
  /// Acceptance tests call [killAllActive] in tearDown so a timed-out host
  /// run cannot leave a `dart run` child holding the temp directory on
  /// Windows.
  static final Set<SpawnedCheckProcess> _active = {};

  /// Stops every child still tracked in [_active] and waits for each exit.
  static Future<void> killAllActive() async {
    final leftover = List<SpawnedCheckProcess>.of(_active);
    for (final process in leftover) {
      await process.kill();
    }
  }

  final Process _process;
  final Duration _killGrace;
  late final Stream<String> _lines;
  late final Future<String> _standardError;
  var _killed = false;

  @override
  Stream<String> get lines => _lines;

  @override
  void send(String line) {
    _process.stdin.writeln(line);
  }

  @override
  Future<void> closeStdin() async {
    try {
      await _process.stdin.close();
    } on IOException {
      // Child already gone.
    }
  }

  @override
  Future<void> kill() async {
    if (_killed) {
      await _process.exitCode;
      return;
    }
    _killed = true;
    _active.remove(this);
    _process.kill();
    try {
      await _process.exitCode.timeout(_killGrace);
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode;
    }
  }

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<String> get standardError => _standardError;

  static Future<String> _readStandardError(Stream<List<int>> stream) {
    final kept = BytesBuilder(copy: false);
    final done = Completer<String>();
    stream.listen(
      (chunk) {
        final room = maxCustomCheckStandardError - kept.length;
        if (room <= 0) return;
        kept.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
      },
      onError: (Object _) {},
      onDone: () =>
          done.complete(utf8.decode(kept.takeBytes(), allowMalformed: true)),
    );
    return done.future;
  }
}

/// Starts [SpawnedCheckProcess] children with SDK and PATH resolution.
final class SpawnedCheckProcessFactory implements CheckProcessFactory {
  /// Creates the factory.
  ///
  /// [sdk] supplies `dart`/`flutter` when the command starts with those names.
  /// [starter] defaults to `Process.start`. [pathEnv] / [pathExt] default to
  /// the process environment.
  new({
    required this.repoRoot,
    this.sdk,
    ProcessStarter? starter,
    bool? isWindows,
    String? pathEnv,
    String? pathExt,
    Duration? killGrace,
    p.Context? context,
  }) : _start = starter ?? Process.start,
       _isWindows = isWindows ?? Platform.isWindows,
       _pathEnv = pathEnv ?? Platform.environment['PATH'] ?? '',
       _pathExt = pathExt ?? Platform.environment['PATHEXT'],
       _killGrace = killGrace ?? _defaultKillGrace,
       _context =
           context ??
           switch (isWindows) {
             null => p.context,
             true => p.windows,
             false => p.posix,
           };

  /// Repository root; relative executables resolve against it.
  final String repoRoot;

  /// Resolved project SDK, when available.
  final ResolvedSdk? sdk;

  final ProcessStarter _start;
  final bool _isWindows;
  final String _pathEnv;
  final String? _pathExt;
  final Duration _killGrace;
  final p.Context _context;

  @override
  Future<CheckProcess> start(
    List<String> command, {
    required String workingDirectory,
  }) async {
    if (command.isEmpty) {
      throw const InternalException(
        'custom check command must be a non-empty list',
      );
    }
    final resolved = _resolveCommand(command);
    final executable = resolved.first;
    final arguments = resolved.sublist(1);
    final unsafe = _unsafeBatchArgument(executable, arguments);
    if (unsafe != null) {
      throw InternalException(
        'unsafe argument for batch executable: '
        '${_truncate(sanitizeForTerminal(unsafe))}',
      );
    }

    final Process process;
    try {
      process = await _start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: false,
      );
    } on ProcessException catch (error) {
      throw InternalException('cannot start: ${error.message}');
    }

    return SpawnedCheckProcess._(process, killGrace: _killGrace);
  }

  List<String> _resolveCommand(List<String> command) {
    final head = command.first;
    final rest = command.sublist(1);

    if (head == 'dart') {
      final dart = sdk?.dartExecutable;
      if (dart == null) {
        throw const InternalException(
          'cannot start: no resolved dart executable',
        );
      }
      return [dart, ...rest];
    }
    if (head == 'flutter') {
      final flutter = sdk?.flutterExecutable;
      if (flutter == null) {
        throw const InternalException(
          'cannot start: no resolved flutter executable',
        );
      }
      return [flutter, ...rest];
    }

    if (_hasSeparator(head)) {
      if (_context.isAbsolute(head)) {
        return [head, ...rest];
      }
      final absolute = _context.normalize(_context.join(repoRoot, head));
      _ensureInsideRepo(absolute);
      return [absolute, ...rest];
    }

    final fromPath = resolvePathExecutable(
      name: head,
      pathEntries: splitPathEnv(_pathEnv, isWindows: _isWindows),
      repoRoot: repoRoot,
      isWindows: _isWindows,
      pathExtensions: pathExtSuffixes(_pathExt),
      context: _context,
    );
    if (fromPath == null) {
      throw InternalException('cannot start: "$head" not found on PATH');
    }
    return [fromPath, ...rest];
  }

  bool _hasSeparator(String name) {
    if (name.contains('/')) return true;
    if (_context.style == p.Style.windows && name.contains(r'\')) {
      return true;
    }
    return false;
  }

  void _ensureInsideRepo(String absolute) {
    String realFile;
    String realRoot;
    try {
      realFile = File(absolute).existsSync()
          ? File(absolute).resolveSymbolicLinksSync()
          : absolute;
      realRoot = Directory(repoRoot).resolveSymbolicLinksSync();
    } on FileSystemException {
      realFile = absolute;
      realRoot = repoRoot;
    }
    if (!_context.equals(realFile, realRoot) &&
        !_context.isWithin(realRoot, realFile)) {
      throw InternalException(
        'cannot start: executable escapes the repository: $absolute',
      );
    }
  }

  String? _unsafeBatchArgument(String executable, List<String> arguments) {
    if (!_isWindows) return null;
    final lower = executable.toLowerCase();
    if (!lower.endsWith('.bat') && !lower.endsWith('.cmd')) return null;
    for (final argument in arguments) {
      if (argument.codeUnits.any(_isUnsafeForBatch)) return argument;
    }
    return null;
  }

  static bool _isUnsafeForBatch(int unit) =>
      unit < 0x20 ||
      unit == 0x7f ||
      _batchMetacharacters.codeUnits.contains(unit);

  static String _truncate(String value) =>
      value.length <= 200 ? value : value.substring(0, 200);
}

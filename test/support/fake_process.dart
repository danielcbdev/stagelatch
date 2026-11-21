import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A [Process] that plays back canned output and records how it was used.
final class FakeProcess implements Process {
  /// Creates a process.
  ///
  /// [stdoutLines] and [standardError] are what the child writes. It exits
  /// with [exitCodeValue] once its output is delivered, unless
  /// [hangsUntilKilled] is set: then it never exits on its own and [kill]
  /// ends it. When [stdoutError] is set, the standard output stream fails
  /// with it after the lines.
  new({
    this.stdoutLines = const [],
    this.standardError = '',
    this.exitCodeValue = 0,
    this.hangsUntilKilled = false,
    this.stdoutError,
  }) {
    unawaited(_stdin.stream.drain<void>());
    unawaited(_play());
  }

  /// What the child writes to standard output, one line each.
  final List<String> stdoutLines;

  /// What the child writes to standard error.
  final String standardError;

  /// The exit code, once the child exits.
  final int exitCodeValue;

  /// Whether the child keeps running until it is killed.
  final bool hangsUntilKilled;

  /// An error the standard output stream ends with, instead of closing.
  final Object? stdoutError;

  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _stdin = StreamController<List<int>>();
  late final IOSink _stdinSink = IOSink(_stdin);
  final _exit = Completer<int>();

  /// The signals sent with [kill], in order.
  final List<ProcessSignal> signals = [];

  /// Whether [kill] was called.
  bool get killed => signals.isNotEmpty;

  /// Whether standard input was closed.
  bool get stdinClosed => _stdin.isClosed;

  Future<void> _play() async {
    for (final line in stdoutLines) {
      _stdout.add(utf8.encode('$line\n'));
    }
    if (standardError.isNotEmpty) _stderr.add(utf8.encode(standardError));
    final failure = stdoutError;
    if (failure != null) _stdout.addError(failure);
    if (hangsUntilKilled) return;
    unawaited(_stderr.close());
    unawaited(_stdout.close());
    if (!_exit.isCompleted) _exit.complete(exitCodeValue);
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  IOSink get stdin => _stdinSink;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_stderr.isClosed) unawaited(_stderr.close());
    if (!_exit.isCompleted) _exit.complete(-15);
    return true;
  }
}

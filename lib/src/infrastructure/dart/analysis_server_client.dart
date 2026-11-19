/// A client of the Dart analysis server's legacy protocol (ADR-0008).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stagelatch/src/application/errors.dart';

/// Talks to `dart language-server --protocol=analyzer` over its standard
/// input and output: newline-delimited JSON, each request with a string id
/// that its response repeats. It opens no socket (security S7).
final class AnalysisServerClient {
  new _(this._process) {
    _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onDone);
    // Drained so a chatty server never blocks on a full pipe.
    _process.stderr.listen((_) {});
  }

  /// Starts the analysis server of the SDK whose `dart` is
  /// [dartExecutable], and waits until it announces itself.
  static Future<AnalysisServerClient> start(String dartExecutable) async {
    final Process process;
    try {
      process = await Process.start(dartExecutable, const [
        // The gate never touches the network (ADR-0003).
        '--suppress-analytics',
        'language-server',
        // The legacy protocol answers getErrors for one file, which LSP
        // does not.
        '--protocol=analyzer',
        '--client-id=stagelatch',
      ]);
    } on ProcessException catch (error) {
      throw InternalException(
        'Cannot start the analysis server: ${error.message}',
        where: 'dart',
      );
    }
    final client = AnalysisServerClient._(process);
    await client._connected.future;
    return client;
  }

  final Process _process;
  final Map<String, Completer<Map<String, Object?>>> _pending = {};
  final Completer<void> _connected = Completer<void>();
  var _nextId = 0;
  var _ended = false;

  /// Sends [method] with [params] and returns the response's `result`.
  ///
  /// Throws [InternalException] when the server answers with an error or
  /// ends before answering.
  Future<Map<String, Object?>> request(
    String method,
    Map<String, Object?> params,
  ) {
    if (_ended) {
      return Future.error(
        InternalException(
          'The analysis server ended before $method.',
          where: 'dart',
        ),
      );
    }
    final id = '${_nextId++}';
    final completer = _pending[id] = Completer<Map<String, Object?>>();
    _process.stdin.writeln(
      jsonEncode({'id': id, 'method': method, 'params': params}),
    );
    return completer.future;
  }

  void _onLine(String line) {
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (json is! Map<String, Object?>) return;
    if (json case {'id': final String id}) {
      final completer = _pending.remove(id);
      if (completer == null) return;
      if (json case {
        'error': {'code': final String code, 'message': final String message},
      }) {
        completer.completeError(
          InternalException('Analysis server: $code $message', where: 'dart'),
        );
      } else {
        completer.complete(switch (json['result']) {
          final Map<String, Object?> result => result,
          _ => const {},
        });
      }
    } else if (json['event'] == 'server.connected' && !_connected.isCompleted) {
      _connected.complete();
    }
  }

  void _onDone() {
    _ended = true;
    const error = InternalException(
      'The analysis server ended unexpectedly.',
      where: 'dart',
    );
    if (!_connected.isCompleted) _connected.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }

  /// Asks the server to shut down and waits for it to exit; kills it if it
  /// has not exited after 5 seconds, so no server outlives a run.
  Future<void> close() async {
    if (!_ended) {
      try {
        await request(
          'server.shutdown',
          const {},
        ).timeout(const Duration(seconds: 5));
      } on Object {
        // Shutting down anyway: the kill below is the guarantee.
      }
    }
    try {
      await _process.stdin.close();
    } on IOException {
      // Already gone.
    }
    final exited = await _process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    if (exited == -1) {
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode;
    }
  }
}

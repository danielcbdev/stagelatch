/// A minimal client of the Dart analysis server's legacy protocol.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// An error response from the server.
final class ServerError implements Exception {
  /// Creates an error for [method] with the server's [code] and [message].
  const new(this.method, this.code, this.message);

  /// The request method that failed.
  final String method;

  /// Protocol error code, for example `FORMAT_WITH_ERRORS`.
  final String code;

  /// Human-readable message.
  final String message;

  @override
  String toString() => 'ServerError($method): $code $message';
}

/// Talks to `dart language-server --protocol=analyzer` over stdin/stdout.
///
/// Requests and responses are newline-delimited JSON. Each request carries
/// an incrementing string id; responses are matched by id. Notifications
/// are delivered on [notifications].
final class ServerClient {
  new _(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
    // Drain stderr so a chatty server never blocks on a full pipe.
    _process.stderr.listen((_) {});
  }

  /// Starts the analysis server of the SDK at [sdkRoot].
  ///
  /// [cacheDir] replaces the server's cache directory, so cold runs can
  /// start empty without touching the user's own cache.
  static Future<ServerClient> start(
    String sdkRoot, {
    required String cacheDir,
  }) async {
    final dart = p.join(
      sdkRoot,
      'bin',
      Platform.isWindows ? 'dart.exe' : 'dart',
    );
    final process = await Process.start(dart, [
      // No analytics: the gate never touches the network (ADR-0003).
      '--suppress-analytics',
      'language-server',
      // The legacy protocol: it has getErrors and format requests that
      // answer for one file, which LSP does not.
      '--protocol=analyzer',
      '--cache=$cacheDir',
      '--client-id=stagelatch-bench',
    ]);
    final client = ServerClient._(process);
    // The server announces itself before it accepts requests.
    await client.notifications.firstWhere(
      (n) => n['event'] == 'server.connected',
    );
    return client;
  }

  final Process _process;
  final _pending = <String, Completer<Map<String, Object?>>>{};
  final _notifications = StreamController<Map<String, Object?>>.broadcast();
  final _connected = Completer<void>();
  var _nextId = 0;

  /// Every notification the server sent, in order.
  Stream<Map<String, Object?>> get notifications => _notifications.stream;

  void _onLine(String line) {
    final json = jsonDecode(line);
    if (json is! Map<String, Object?>) return;
    if (json case {'id': final String id}) {
      final completer = _pending.remove(id);
      if (completer == null) return;
      if (json case {
        'error': {'code': final String code, 'message': final String message},
      }) {
        completer.completeError(ServerError(id, code, message));
      } else {
        completer.complete(switch (json['result']) {
          final Map<String, Object?> result => result,
          _ => const {},
        });
      }
    } else if (json.containsKey('event')) {
      if (json['event'] == 'server.connected' && !_connected.isCompleted) {
        _connected.complete();
      }
      _notifications.add(json);
    }
  }

  /// Sends [method] with [params] and returns the `result` object.
  ///
  /// Throws a [ServerError] when the server answers with an error.
  Future<Map<String, Object?>> request(
    String method,
    Map<String, Object?> params,
  ) {
    final id = '${_nextId++}';
    final completer = _pending[id] = Completer<Map<String, Object?>>();
    _process.stdin.writeln(
      jsonEncode({'id': id, 'method': method, 'params': params}),
    );
    return completer.future;
  }

  /// Asks the server to shut down, then waits for the process to exit.
  ///
  /// Kills the process if it is still alive after a short grace period, so
  /// no server survives a run (a survivor would turn the next run into a
  /// daemon measurement).
  Future<void> close() async {
    try {
      await request(
        'server.shutdown',
        const {},
      ).timeout(const Duration(seconds: 5));
    } on Object {
      // Shutting down anyway: the kill below is the guarantee.
    }
    await _process.stdin.close();
    final exited = await _process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    if (exited == -1) {
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode;
    }
    await _notifications.close();
  }
}

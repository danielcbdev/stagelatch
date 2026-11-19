/// Blob content and sizes through persistent `git cat-file` processes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/infrastructure/git/byte_stream_reader.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';

/// Reads objects by id through one long-lived `git cat-file --batch`
/// process, and sizes through one `--batch-check` process (ADR-0001).
///
/// A commit hook reads many files; one spawn per file would spend the whole
/// time budget starting git. Each process is started on first use, so a run
/// that reads nothing spawns nothing.
///
/// Objects are addressed by id, never by path, so no file name ever needs
/// quoting on the pipe.
final class CatFileBatch {
  /// Creates a reader that starts git through [_git].
  new(this._git);

  /// A SHA-1 or SHA-256 object id. Two fixed-length character classes, so
  /// matching is linear (security rule S6). Rejecting everything else keeps
  /// revision syntax and embedded newlines off the pipe.
  static final _objectId = RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$');

  final GitProcess _git;

  _Channel? _content;
  _Channel? _sizes;
  bool _closed = false;
  int _spawnCount = 0;

  /// The tail of the request queue. A request starts only when the one
  /// before it has finished, so a single request is ever on a pipe.
  Future<void> _queue = Future.value();

  /// How many git processes this reader has started. For tests.
  int get spawnCount => _spawnCount;

  /// The content of the object [blobId].
  ///
  /// Throws [ArgumentError] when [blobId] is not an object id,
  /// [InternalException] when git does not have the object, and
  /// [StateError] after [close].
  Future<Uint8List> read(String blobId) => _enqueue(blobId, () async {
    // --batch: answer each id with a header line and the raw content.
    final channel = _content ??= await _open('--batch');
    final size = await _request(channel, blobId);
    final bytes = await channel.reader.readBytes(size);
    // The content is followed by one line feed that is not part of it.
    await channel.reader.readBytes(1);
    return bytes;
  });

  /// The size in bytes of the object [blobId], without reading it.
  ///
  /// Fails as [read] does.
  Future<int> size(String blobId) => _enqueue(blobId, () async {
    // --batch-check: answer each id with the header line only.
    final channel = _sizes ??= await _open('--batch-check');
    return await _request(channel, blobId);
  });

  /// Ends both processes. Safe to call more than once.
  ///
  /// Closing standard input is how `cat-file` is told to exit.
  Future<void> close() async {
    _closed = true;
    await _queue;
    for (final channel in [_content, _sizes].nonNulls) {
      // A paused stdout listener would keep the process alive after main
      // returns (a commit hook would never finish). Cancel it, then stop
      // git. stdin.close() can itself fail to complete once git is idle.
      await channel.reader.close();
      channel.process.kill();
      await channel.process.exitCode;
    }
    _content = null;
    _sizes = null;
  }

  /// Validates [blobId] and appends [action] to the request queue.
  Future<T> _enqueue<T>(String blobId, Future<T> Function() action) {
    if (_closed) throw StateError('This reader is closed.');
    if (!_objectId.hasMatch(blobId)) {
      throw ArgumentError.value(blobId, 'blobId', 'Not a git object id');
    }
    final result = _queue.then((_) => action());
    // The queue must survive a failed request: the next one still runs.
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<_Channel> _open(String mode) async {
    _spawnCount++;
    final process = await _git.start(['cat-file', mode]);
    // Nothing useful arrives on stderr, but an unread pipe that fills up
    // would block git, so it is drained for the life of the process.
    unawaited(process.stderr.drain<void>());
    return _Channel(process, ByteStreamReader(process.stdout));
  }

  /// Sends [blobId] and returns the object size from the header line:
  /// `<id> <type> <size>`, or `<id> missing`.
  Future<int> _request(_Channel channel, String blobId) async {
    channel.process.stdin.add(utf8.encode('$blobId\n'));
    await channel.process.stdin.flush();
    final header = await channel.reader.readLine();
    if (header == null) {
      throw const InternalException(
        'git cat-file ended unexpectedly.',
        where: 'git',
      );
    }
    final fields = header.split(' ');
    if (fields.length == 2 && fields[1] == 'missing') {
      throw InternalException(
        'Object $blobId is missing from the repository.',
        where: 'git',
      );
    }
    final size = fields.length == 3 ? int.tryParse(fields[2]) : null;
    if (size == null) {
      throw InternalException(
        'Unexpected answer from git cat-file: $header',
        where: 'git',
      );
    }
    return size;
  }
}

/// One running `cat-file` process and the reader over its output.
final class _Channel {
  const new(this.process, this.reader);

  final Process process;
  final ByteStreamReader reader;
}

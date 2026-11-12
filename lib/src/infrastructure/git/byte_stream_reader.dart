/// Pull-style reading from a stream of byte chunks.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

/// Reads lines and exact byte counts from a stream that delivers bytes in
/// arbitrary chunks, such as the standard output of a process.
///
/// `git cat-file --batch` answers with a text header followed by a known
/// number of raw bytes; this is what lets one reader consume both.
///
/// One caller at a time: reads must not overlap.
final class ByteStreamReader {
  /// Creates a reader over [stream]. The stream is listened to lazily.
  new(Stream<List<int>> stream) : _chunks = StreamIterator(stream);

  /// The byte value of a line feed.
  static const int _lineFeed = 0x0A;

  final StreamIterator<List<int>> _chunks;

  /// The chunk being consumed, and how far into it we are.
  List<int> _current = const [];
  int _position = 0;

  /// Reads up to the next line feed and returns the bytes before it, one
  /// character per byte. The line feed is consumed and not returned.
  ///
  /// Returns null when the stream has ended and no byte is left. Throws
  /// [StateError] when the stream ends after some bytes but before a line
  /// feed.
  Future<String?> readLine() async {
    final line = <int>[];
    while (true) {
      if (_position >= _current.length && !await _advance()) {
        if (line.isEmpty) return null;
        throw StateError('The stream ended in the middle of a line.');
      }
      final end = _current.indexOf(_lineFeed, _position);
      if (end < 0) {
        line.addAll(_current.getRange(_position, _current.length));
        _position = _current.length;
        continue;
      }
      line.addAll(_current.getRange(_position, end));
      _position = end + 1;
      return String.fromCharCodes(line);
    }
  }

  /// Reads exactly [count] bytes.
  ///
  /// Throws [StateError] when the stream ends first.
  Future<Uint8List> readBytes(int count) async {
    final result = Uint8List(count);
    var filled = 0;
    while (filled < count) {
      if (_position >= _current.length && !await _advance()) {
        throw StateError('The stream ended after $filled of $count bytes.');
      }
      final take = math.min(count - filled, _current.length - _position);
      result.setRange(filled, filled + take, _current, _position);
      filled += take;
      _position += take;
    }
    return result;
  }

  /// Moves to the next chunk. Returns false at the end of the stream.
  Future<bool> _advance() async {
    if (!await _chunks.moveNext()) return false;
    _current = _chunks.current;
    _position = 0;
    return true;
  }
}

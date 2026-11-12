import 'package:stagelatch/src/infrastructure/git/byte_stream_reader.dart';
import 'package:test/test.dart';

ByteStreamReader _reader(List<List<int>> chunks) =>
    ByteStreamReader(Stream.fromIterable(chunks));

void main() {
  group('ByteStreamReader.readLine', () {
    test('returns a line without its line feed', () async {
      final reader = _reader(['abc 3\nrest'.codeUnits]);

      expect(await reader.readLine(), 'abc 3');
    });

    test('joins a line split across chunks', () async {
      final reader = _reader([
        'ab'.codeUnits,
        <int>[],
        'c\nd'.codeUnits,
        '\n'.codeUnits,
      ]);

      expect(await reader.readLine(), 'abc');
      expect(await reader.readLine(), 'd');
    });

    test('returns null at the end of the stream', () async {
      final reader = _reader(['a\n'.codeUnits]);

      expect(await reader.readLine(), 'a');
      expect(await reader.readLine(), isNull);
    });

    test('fails when the stream ends in the middle of a line', () async {
      final reader = _reader(['partial'.codeUnits]);

      expect(reader.readLine, throwsStateError);
    });
  });

  group('ByteStreamReader.readBytes', () {
    test('returns exactly the requested bytes, across chunks', () async {
      final reader = _reader([
        [1, 2],
        [3],
        [4, 5, 6],
      ]);

      expect(await reader.readBytes(4), [1, 2, 3, 4]);
      expect(await reader.readBytes(2), [5, 6]);
    });

    test('returns an empty list for zero bytes without reading', () async {
      final reader = _reader([]);

      expect(await reader.readBytes(0), isEmpty);
    });

    test('keeps bytes that look like line feeds or NUL', () async {
      final reader = _reader([
        [0x0A, 0x00, 0x0D, 0x0A],
      ]);

      expect(await reader.readBytes(4), [0x0A, 0x00, 0x0D, 0x0A]);
    });

    test('fails when the stream ends early', () async {
      final reader = _reader([
        [1, 2],
      ]);

      expect(() => reader.readBytes(3), throwsStateError);
    });
  });

  test('lines and byte blocks can be interleaved', () async {
    final reader = _reader(['id blob 3\nA\nB\nid2 blob 1\nZ\n'.codeUnits]);

    expect(await reader.readLine(), 'id blob 3');
    expect(await reader.readBytes(3), 'A\nB'.codeUnits);
    expect(await reader.readBytes(1), '\n'.codeUnits);
    expect(await reader.readLine(), 'id2 blob 1');
    expect(await reader.readBytes(1), 'Z'.codeUnits);
  });
}

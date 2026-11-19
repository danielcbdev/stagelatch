import 'dart:convert';
import 'dart:typed_data';

import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:test/test.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  group('decodeSnapshotText', () {
    test('decodes UTF-8', () {
      expect(decodeSnapshotText(_bytes(utf8.encode('ação\n'))), 'ação\n');
    });

    test('keeps CRLF line endings as stored', () {
      expect(decodeSnapshotText(_bytes(utf8.encode('a\r\nb'))), 'a\r\nb');
    });

    test('strips one leading byte order mark', () {
      expect(decodeSnapshotText(_bytes([0xEF, 0xBB, 0xBF, 0x61])), 'a');
    });

    test('is null for content with a NUL in the first 8000 bytes', () {
      expect(decodeSnapshotText(_bytes([0x61, 0x00, 0x62])), isNull);
      expect(
        decodeSnapshotText(_bytes([...List.filled(7999, 0x61), 0x00])),
        isNull,
      );
    });

    test('does not treat a NUL after the first 8000 bytes as binary', () {
      final text = decodeSnapshotText(
        _bytes([...List.filled(8000, 0x61), 0x00]),
      );

      expect(text, hasLength(8001));
    });

    test('is null for bytes that are not valid UTF-8', () {
      expect(decodeSnapshotText(_bytes([0xC3, 0x28])), isNull);
    });

    test('is null above the size limit and not at it', () {
      expect(
        decodeSnapshotText(Uint8List(maxTextBytes + 1)..fillRange(0, 9, 0x61)),
        isNull,
      );
      expect(
        decodeSnapshotText(
          Uint8List(maxTextBytes)..fillRange(0, maxTextBytes, 0x61),
        ),
        hasLength(maxTextBytes),
      );
    });

    test('decodes empty content as an empty string', () {
      expect(decodeSnapshotText(Uint8List(0)), '');
    });
  });
}

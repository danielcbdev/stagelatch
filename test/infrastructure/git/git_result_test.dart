import 'dart:convert';
import 'dart:typed_data';

import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/infrastructure/git/git_result.dart';
import 'package:test/test.dart';

GitResult _result(List<int> stdout) =>
    GitResult(exitCode: 0, stdout: Uint8List.fromList(stdout), stderr: '');

void main() {
  group('GitResult.nulSeparated', () {
    test('splits on NUL and drops the trailing terminator', () {
      final result = _result(utf8.encode('a b.txt\u0000ação.txt\u0000'));

      expect(result.nulSeparated, ['a b.txt', 'ação.txt']);
    });

    test('keeps a newline inside a field', () {
      final result = _result(utf8.encode('new\nline.txt\u0000'));

      expect(result.nulSeparated, ['new\nline.txt']);
    });

    test('is empty for empty output', () {
      expect(_result(const []).nulSeparated, isEmpty);
    });

    test('keeps an empty field that is not the last', () {
      final result = _result(utf8.encode('a\u0000\u0000b\u0000'));

      expect(result.nulSeparated, ['a', '', 'b']);
    });

    test('reports a path that is not valid UTF-8 as a usage error', () {
      final result = _result([0x61, 0xFF, 0xFE, 0x00]);

      expect(
        () => result.nulSeparated,
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            'A path in this repository is not valid UTF-8: 61 ff fe.',
          ),
        ),
      );
    });
  });

  group('GitResult.text', () {
    test('decodes standard output as UTF-8', () {
      expect(_result(utf8.encode('main\n')).text, 'main\n');
    });

    test('never throws on malformed bytes', () {
      expect(_result([0x61, 0xFF]).text, 'a�');
    });
  });
}

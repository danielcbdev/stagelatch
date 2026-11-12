@Tags(['git'])
library;

import 'dart:convert';

import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/infrastructure/git/cat_file_batch.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

void main() {
  late TempRepo repo;
  late CatFileBatch batch;

  /// Stages [bytes] at [path] and returns the blob id git gave them.
  Future<String> blobOf(String path, List<int> bytes) async {
    await repo.writeBytes(path, bytes);
    await repo.stage(path);
    return (await repo.git(['rev-parse', ':$path'])).trim();
  }

  setUp(() async {
    repo = await TempRepo.create();
    batch = CatFileBatch(
      GitProcess(workingDirectory: repo.root, environment: repo.environment),
    );
  });

  tearDown(() async {
    await batch.close();
    await repo.dispose();
  });

  group('CatFileBatch.read', () {
    test('reads a blob byte for byte, including NUL and CRLF', () async {
      const bytes = [0x41, 0x00, 0x0D, 0x0A, 0x42];
      final id = await blobOf('a.bin', bytes);

      expect(await batch.read(id), bytes);
    });

    test('reads an empty blob', () async {
      final id = await blobOf('empty.txt', const []);

      expect(await batch.read(id), isEmpty);
    });

    test('reads a blob larger than one pipe buffer', () async {
      final bytes = List<int>.generate(1 << 20, (index) => index % 251);
      final id = await blobOf('big.bin', bytes);

      expect(await batch.read(id), bytes);
    });

    test('serves many reads from one process', () async {
      final id = await blobOf('a.txt', utf8.encode('content'));

      for (var i = 0; i < 100; i++) {
        await batch.read(id);
      }

      expect(batch.spawnCount, 1);
    });

    test('answers concurrent reads each with its own content', () async {
      final ids = [
        for (var i = 0; i < 20; i++)
          await blobOf('f$i.txt', utf8.encode('content of file $i\n')),
      ];

      final contents = await Future.wait(ids.map(batch.read));

      expect(contents.map(utf8.decode), [
        for (var i = 0; i < 20; i++) 'content of file $i\n',
      ]);
    });

    test('an unknown id is an internal error', () {
      expect(
        () => batch.read('0' * 40),
        throwsA(
          isA<InternalException>().having(
            (error) => error.message,
            'message',
            'Object ${'0' * 40} is missing from the repository.',
          ),
        ),
      );
    });

    test('keeps working after an unknown id', () async {
      final id = await blobOf('a.txt', utf8.encode('still here'));

      await expectLater(
        () => batch.read('0' * 40),
        throwsA(isA<InternalException>()),
      );

      expect(utf8.decode(await batch.read(id)), 'still here');
    });

    test('rejects anything that is not an object id', () {
      for (final bad in ['HEAD', ':README.md', 'abc\nHEAD', '', 'g' * 40]) {
        expect(() => batch.read(bad), throwsArgumentError, reason: bad);
      }
    });
  });

  group('CatFileBatch.size', () {
    test('returns the size without the content', () async {
      final id = await blobOf('a.bin', const [1, 2, 3, 4, 5]);

      expect(await batch.size(id), 5);
    });

    test('uses its own single process', () async {
      final id = await blobOf('a.txt', utf8.encode('x'));

      await batch.size(id);
      await batch.size(id);
      await batch.read(id);

      expect(batch.spawnCount, 2);
    });
  });

  group('CatFileBatch.close', () {
    test('ends the processes, and a later read fails', () async {
      final id = await blobOf('a.txt', utf8.encode('x'));
      await batch.read(id);

      await batch.close();

      expect(() => batch.read(id), throwsStateError);
    });

    test('may be called twice, and before any read', () async {
      await batch.close();
      await batch.close();

      expect(batch.spawnCount, 0);
    });
  });
}

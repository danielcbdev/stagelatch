import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/infrastructure/io/file_cache.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String common;
  late FileCache cache;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('stagelatch_cache_');
    // macOS hands out /var/..., a symlink to /private/var/...
    common = p.join(temp.resolveSymbolicLinksSync(), 'git');
    await Directory(common).create();
    cache = FileCache(commonDir: common);
  });

  tearDown(() async {
    if (temp.existsSync()) {
      if (!Platform.isWindows) {
        await Process.run('chmod', ['-R', 'u+rwx', temp.path]);
      }
      await temp.delete(recursive: true);
    }
  });

  test('a value written is read back; an unknown key is null', () async {
    expect(await cache.read('facts-v1', 'abcdef-12'), isNull);

    await cache.write('facts-v1', 'abcdef-12', 'hello');

    expect(await cache.read('facts-v1', 'abcdef-12'), 'hello');
    expect(await cache.read('facts-v1', 'abcdef-13'), isNull);
    expect(await cache.read('facts-v2', 'abcdef-12'), isNull);
  });

  test(
    'an entry is stored under stagelatch/cache/<namespace>/<shard>/<key>',
    () async {
      await cache.write('facts-v1', 'abcdef-12', 'v');

      expect(
        File(
          p.join(common, 'stagelatch', 'cache', 'facts-v1', 'ab', 'abcdef-12'),
        ).readAsStringSync(),
        'v',
      );
    },
  );

  test('a value keeps its exact characters', () async {
    const value = 'line\r\nüñí \u{1F600}\n';

    await cache.write('facts-v1', 'abcd', value);

    expect(await cache.read('facts-v1', 'abcd'), value);
  });

  test('a namespace or key outside the allowed alphabet is an '
      'ArgumentError', () {
    expect(() => cache.write('facts', '../x', 'v'), throwsArgumentError);
    expect(() => cache.write('facts', 'a.b', 'v'), throwsArgumentError);
    expect(() => cache.write('facts', 'ABCD', 'v'), throwsArgumentError);
    expect(() => cache.write('Facts', 'abcd', 'v'), throwsArgumentError);
    expect(() => cache.write('facts', 'a', 'v'), throwsArgumentError);
    expect(() => cache.write('', 'abcd', 'v'), throwsArgumentError);
    expect(() => cache.write('a/b', 'abcd', 'v'), throwsArgumentError);
    expect(() => cache.read('facts', '../x'), throwsArgumentError);
    expect(() => cache.read('../facts', 'abcd'), throwsArgumentError);
  });

  test('the constructor and read create nothing', () async {
    await cache.read('facts-v1', 'abcdef-12');

    expect(Directory(p.join(common, 'stagelatch')).existsSync(), isFalse);
  });

  test('a reader never sees a partial entry', () async {
    final value = 'x' * (1024 * 1024);
    final seen = <String?>[];

    final writer = cache.write('facts-v1', 'abcd', value);
    for (var i = 0; i < 200; i++) {
      seen.add(await cache.read('facts-v1', 'abcd'));
    }
    await writer;
    seen.add(await cache.read('facts-v1', 'abcd'));

    expect(seen, everyElement(anyOf(isNull, equals(value))));
    expect(seen.last, value);
  });

  test('200 concurrent reads during a rewrite see a whole value', () async {
    final old = 'a' * (1024 * 1024);
    final fresh = 'b' * (1024 * 1024);
    await cache.write('facts-v1', 'abcd', old);

    final writer = cache.write('facts-v1', 'abcd', fresh);
    final reads = await Future.wait([
      for (var i = 0; i < 200; i++) cache.read('facts-v1', 'abcd'),
    ]);
    await writer;

    expect(reads, everyElement(anyOf(equals(old), equals(fresh))));
  });

  test('twenty concurrent writers of one key leave one complete entry and no '
      'temporary directory', () async {
    final value = 'y' * 100000;

    await Future.wait([
      for (var i = 0; i < 20; i++) cache.write('facts-v1', 'abcd', value),
    ]);

    final shard = Directory(
      p.join(common, 'stagelatch', 'cache', 'facts-v1', 'ab'),
    );
    expect(shard.listSync().map((e) => p.basename(e.path)), ['abcd']);
    expect(await cache.read('facts-v1', 'abcd'), value);
  });

  test(
    'a rename that fails is not an error and keeps the existing entry',
    () async {
      await cache.write('facts-v1', 'abcd', 'first');
      final failing = FileCache(
        commonDir: common,
        rename: (from, to) =>
            throw const FileSystemException('refused (rename over existing)'),
      );

      await failing.write('facts-v1', 'abcd', 'second');
      await failing.write('facts-v1', 'ffff', 'new');

      expect(await cache.read('facts-v1', 'abcd'), 'first');
      expect(await cache.read('facts-v1', 'ffff'), isNull);
      final shard = Directory(
        p.join(common, 'stagelatch', 'cache', 'facts-v1', 'ab'),
      );
      // The temporary directory is gone too.
      expect(shard.listSync().map((e) => p.basename(e.path)), ['abcd']);
    },
  );

  test('an unwritable directory makes write a no-op and read a miss', () async {
    await cache.write('facts-v1', 'abcd', 'there');
    final root = Directory(p.join(common, 'stagelatch', 'cache'));
    await Process.run('chmod', ['-R', '0000', root.path]);

    final fresh = FileCache(commonDir: common);
    await fresh.write('facts-v1', 'ffff', 'new');
    final read = await fresh.read('facts-v1', 'abcd');
    await Process.run('chmod', ['-R', 'u+rwx', root.path]);

    expect(read, isNull);
    expect(
      File(p.join(root.path, 'facts-v1', 'ff', 'ffff')).existsSync(),
      isFalse,
    );
  }, testOn: '!windows');

  test(
    'a common directory that cannot be written makes write a no-op',
    () async {
      await Process.run('chmod', ['0500', common]);

      await cache.write('facts-v1', 'abcd', 'v');

      expect(await cache.read('facts-v1', 'abcd'), isNull);
      expect(Directory(p.join(common, 'stagelatch')).existsSync(), isFalse);
    },
    testOn: '!windows',
  );

  test('a common directory that does not exist makes write a no-op', () async {
    final missing = FileCache(commonDir: p.join(temp.path, 'nowhere'));

    await missing.write('facts-v1', 'abcd', 'v');

    expect(await missing.read('facts-v1', 'abcd'), isNull);
    expect(Directory(p.join(temp.path, 'nowhere')).existsSync(), isFalse);
  });

  test('a stagelatch directory that is a symlink out of the common directory '
      'is not used', () async {
    final outside = Directory(p.join(temp.path, 'outside'))..createSync();
    Link(p.join(common, 'stagelatch')).createSync(outside.path);

    await cache.write('facts-v1', 'abcd', 'v');

    expect(outside.listSync(), isEmpty);
    expect(await cache.read('facts-v1', 'abcd'), isNull);
  }, testOn: '!windows');

  test('a cache directory that is a symlink out of the common directory is '
      'not used', () async {
    final outside = Directory(p.join(temp.path, 'outside'))..createSync();
    Directory(p.join(common, 'stagelatch')).createSync();
    Link(p.join(common, 'stagelatch', 'cache')).createSync(outside.path);

    await cache.write('facts-v1', 'abcd', 'v');

    expect(outside.listSync(), isEmpty);
    expect(await cache.read('facts-v1', 'abcd'), isNull);
  }, testOn: '!windows');

  test('a symlink that stays inside the common directory is used', () async {
    final inside = Directory(p.join(common, 'elsewhere'))..createSync();
    Link(p.join(common, 'stagelatch')).createSync(inside.path);

    await cache.write('facts-v1', 'abcd', 'v');

    expect(await cache.read('facts-v1', 'abcd'), 'v');
    expect(
      File(p.join(inside.path, 'cache', 'facts-v1', 'ab', 'abcd')).existsSync(),
      isTrue,
    );
  }, testOn: '!windows');

  test('a common directory reached through a symlink works', () async {
    final link = p.join(temp.path, 'link');
    Link(link).createSync(common);
    final viaLink = FileCache(commonDir: link);

    await viaLink.write('facts-v1', 'abcd', 'v');

    expect(await cache.read('facts-v1', 'abcd'), 'v');
  }, testOn: '!windows');

  test('a file where the cache directory should be is not an error', () async {
    File(p.join(common, 'stagelatch')).writeAsStringSync('not a directory');

    await cache.write('facts-v1', 'abcd', 'v');

    expect(await cache.read('facts-v1', 'abcd'), isNull);
  });

  test('a directory where an entry should be reads as a miss', () async {
    await cache.write('facts-v1', 'abcd', 'v');
    final entry = p.join(
      common,
      'stagelatch',
      'cache',
      'facts-v1',
      'ab',
      'abcd',
    );
    File(entry).deleteSync();
    Directory(entry).createSync();

    expect(await cache.read('facts-v1', 'abcd'), isNull);
  });

  test('an entry that is not valid UTF-8 reads as a miss', () async {
    await cache.write('facts-v1', 'abcd', 'v');
    File(p.join(common, 'stagelatch', 'cache', 'facts-v1', 'ab', 'abcd'))
        .writeAsBytesSync([0xff, 0xfe, 0xfd]);

    expect(await cache.read('facts-v1', 'abcd'), isNull);
  });
}

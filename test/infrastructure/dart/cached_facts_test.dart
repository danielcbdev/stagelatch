import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:stagelatch/src/infrastructure/dart/cached_facts.dart';
import 'package:stagelatch/src/infrastructure/dart/facts_codec.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';
import 'package:test/test.dart';

import '../../support/fake_cache.dart';
import '../../support/fake_snapshot_files.dart';

/// A snapshot that counts how often the content is read.
final class _CountingSnapshot implements SnapshotFiles {
  new(this._inner);

  final SnapshotFiles _inner;
  int textReads = 0;

  @override
  Future<SnapshotEntry?> entry(RepoPath path) => _inner.entry(path);

  @override
  Future<List<SnapshotEntry>> list({RepoPath? under}) =>
      _inner.list(under: under);

  @override
  Future<Uint8List?> readBytes(RepoPath path) => _inner.readBytes(path);

  @override
  Future<String?> readText(RepoPath path) {
    textReads++;
    return _inner.readText(path);
  }

  @override
  Future<int?> size(RepoPath path) => _inner.size(path);
}

const _source =
    "import 'a.dart';\n\nvoid main() {\n  test('t', () {}, solo: true);\n}\n";

String _hash(Iterable<String> functions) =>
    sha256.convert(utf8.encode(([...functions]..sort()).join('\n'))).toString();

void main() {
  late FakeCache cache;

  setUp(() => cache = FakeCache());

  CachedFacts make({Set<String> functions = defaultTestFunctions}) =>
      CachedFacts(
        extractor: SyntacticFacts(testFunctions: functions),
        cache: cache,
      );

  test('the first request extracts and stores; the second is served without '
      'reading the blob', () async {
    final files = _CountingSnapshot(FakeSnapshotFiles({'lib/a.dart': _source}));
    final path = RepoPath('lib/a.dart');

    final first = await make().facts(files, path);
    final reads = files.textReads;
    final second = await make().facts(files, path);

    expect(reads, 1);
    expect(files.textReads, reads, reason: 'a hit does not read the blob');
    expect(cache.writes, hasLength(1));
    expect(encodeFacts(second!), encodeFacts(first!));
    expect(first.directives.single.uri, 'a.dart');
    expect(first.testCalls.single.solo, isNotNull);
  });

  test('a hit equals recomputation, with the requested path in every '
      'location', () async {
    final files = FakeSnapshotFiles({'a.dart': _source, 'lib/b.dart': _source});
    final first = await make().facts(files, RepoPath('a.dart'));

    final hit = await make().facts(files, RepoPath('lib/b.dart'));
    final recomputed = const SyntacticFacts().extract(
      _source,
      RepoPath('lib/b.dart'),
    );

    expect(cache.writes, hasLength(1), reason: 'one blob, one entry');
    expect(encodeFacts(hit!), encodeFacts(recomputed));
    expect(hit.directives.single.location.path, RepoPath('lib/b.dart'));
    expect(hit.testCalls.single.location.path, RepoPath('lib/b.dart'));
    expect(first!.directives.single.location.path, RepoPath('a.dart'));
  });

  test('the key is <blob id>-<sha256 of the sorted test functions>', () async {
    final files = FakeSnapshotFiles({'a.dart': _source});
    final blob = (await files.entry(RepoPath('a.dart')))!.blobId;

    await make(functions: {'zeta', 'alpha'}).facts(files, RepoPath('a.dart'));

    expect(cache.writes, [
      'facts-v$factsFormatVersion/$blob-${_hash(['alpha', 'zeta'])}',
    ]);
    expect(cache.reads, cache.writes);
    expect(factsFormatVersion, 1);
  });

  test('the same functions in another order share the key', () async {
    final files = FakeSnapshotFiles({'a.dart': _source});

    await make(functions: {'b', 'a', 'c'}).facts(files, RepoPath('a.dart'));
    await make(functions: {'c', 'a', 'b'}).facts(files, RepoPath('a.dart'));

    expect(cache.writes, hasLength(1));
  });

  test('different test functions never share an entry', () async {
    final files = FakeSnapshotFiles({
      'a_test.dart': "void main() {\n  myTest('x', () {});\n}\n",
    });
    final path = RepoPath('a_test.dart');

    final plain = await make(functions: {'test'}).facts(files, path);
    final custom = await make(functions: {'test', 'myTest'}).facts(files, path);
    final plainAgain = await make(functions: {'test'}).facts(files, path);

    expect(plain!.testCalls, isEmpty);
    expect(custom!.testCalls.map((c) => c.function), ['myTest']);
    expect(plainAgain!.testCalls, isEmpty);
    expect(cache.entries, hasLength(2));
  });

  test('a corrupted entry is a miss and is overwritten', () async {
    final files = FakeSnapshotFiles({'a.dart': _source});
    await make().facts(files, RepoPath('a.dart'));
    final key = cache.entries.keys.single;
    final good = cache.entries[key]!;
    cache.entries[key] = good.substring(0, good.length ~/ 2);

    final facts = await make().facts(files, RepoPath('a.dart'));

    expect(facts!.directives.single.uri, 'a.dart');
    expect(cache.entries[key], good);
    expect(cache.writes, hasLength(2));
  });

  test('an entry of another version is a miss', () async {
    final files = FakeSnapshotFiles({'a.dart': _source});
    await make().facts(files, RepoPath('a.dart'));
    final key = cache.entries.keys.single;
    cache.entries[key] = cache.entries[key]!.replaceFirst('"v":1', '"v":9');

    final facts = await make().facts(files, RepoPath('a.dart'));

    expect(facts!.testCalls, hasLength(1));
    expect(cache.entries[key], contains('"v":1'));
  });

  test('an exception from the cache is a miss', () async {
    cache = FakeCache(failing: true);
    final files = FakeSnapshotFiles({'a.dart': _source});

    final facts = await make().facts(files, RepoPath('a.dart'));

    expect(facts!.directives.single.uri, 'a.dart');
    expect(cache.reads, hasLength(1));
    expect(cache.writes, hasLength(1));
  });

  test('a symlink, a gitlink, an absent file and a binary file give null and '
      'store nothing', () async {
    final files = FakeSnapshotFiles(
      {
        'link.dart': _source,
        'sub.dart': _source,
        'bin.dart': [0, 1, 2, 3],
      },
      modes: {'link.dart': FileMode.symlink, 'sub.dart': FileMode.gitlink},
    );

    for (final path in ['link.dart', 'sub.dart', 'bin.dart', 'absent.dart']) {
      expect(await make().facts(files, RepoPath(path)), isNull, reason: path);
    }

    expect(cache.writes, isEmpty);
    expect(cache.entries, isEmpty);
  });

  test('an executable file is cached like a regular one', () async {
    final files = FakeSnapshotFiles(
      {'run.dart': _source},
      modes: {'run.dart': FileMode.executable},
    );

    final facts = await make().facts(files, RepoPath('run.dart'));

    expect(facts!.directives, hasLength(1));
    expect(cache.writes, hasLength(1));
  });

  test('a file that is not well formed is cached and restored as not well '
      'formed', () async {
    final files = FakeSnapshotFiles({
      'a.dart': "import 'b.dart';\nvoid main() { print('open); }\n",
    });
    final first = await make().facts(files, RepoPath('a.dart'));

    final second = await make().facts(files, RepoPath('a.dart'));

    expect(first!.isWellFormed, isFalse);
    expect(second!.isWellFormed, isFalse);
    expect(second.directives.single.uri, 'b.dart');
    expect(cache.writes, hasLength(1));
  });
}

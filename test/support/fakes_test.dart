import 'dart:convert';

import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:test/test.dart';

import 'fake_check_context.dart';
import 'fake_documents.dart';
import 'fake_snapshot_files.dart';

final class _Settings {
  const new(this.value);

  final int value;
}

void main() {
  group('FakeSnapshotFiles', () {
    test('readText returns text, and null for a missing file', () async {
      final files = FakeSnapshotFiles({'a.txt': 'hi'});

      expect(await files.readText(RepoPath('a.txt')), 'hi');
      expect(await files.readText(RepoPath('missing')), isNull);
    });

    test('readText is null for bytes containing NUL', () async {
      final files = FakeSnapshotFiles({
        'a.bin': [0, 1, 2],
      });

      expect(await files.readText(RepoPath('a.bin')), isNull);
      expect(await files.readBytes(RepoPath('a.bin')), [0, 1, 2]);
    });

    test('readText is null for bytes that are not valid UTF-8', () async {
      final files = FakeSnapshotFiles({
        'a.txt': [0xC3, 0x28],
      });

      expect(await files.readText(RepoPath('a.txt')), isNull);
    });

    test('readText is null for symlinks and gitlinks', () async {
      final files = FakeSnapshotFiles(
        {'link': 'target', 'vendor/lib': 'abc'},
        modes: {'link': FileMode.symlink, 'vendor/lib': FileMode.gitlink},
      );

      expect(await files.readText(RepoPath('link')), isNull);
      expect(await files.readText(RepoPath('vendor/lib')), isNull);
      expect((await files.entry(RepoPath('link')))?.mode, FileMode.symlink);
    });

    test('readText is null above the size limit', () async {
      final files = FakeSnapshotFiles({
        'big.txt': List<int>.filled(maxTextBytes + 1, 0x61),
        'edge.txt': List<int>.filled(maxTextBytes, 0x61),
      });

      expect(await files.readText(RepoPath('big.txt')), isNull);
      expect(
        await files.readText(RepoPath('edge.txt')),
        hasLength(maxTextBytes),
      );
    });

    test('readText strips a byte order mark and keeps CRLF', () async {
      final files = FakeSnapshotFiles({
        'a.txt': [0xEF, 0xBB, 0xBF, ...utf8.encode('a\r\nb')],
      });

      expect(await files.readText(RepoPath('a.txt')), 'a\r\nb');
    });

    test('list is sorted and can be limited to a directory', () async {
      final files = FakeSnapshotFiles({
        'lib/b.dart': '',
        'lib/a.dart': '',
        'library/c.dart': '',
        'README.md': '',
      });

      expect((await files.list()).map((entry) => entry.path.value), [
        'README.md',
        'lib/a.dart',
        'lib/b.dart',
        'library/c.dart',
      ]);
      expect(
        (await files.list(under: RepoPath('lib')))
            .map((entry) => entry.path.value),
        ['lib/a.dart', 'lib/b.dart'],
      );
    });

    test('blob ids follow content, not path', () async {
      final files = FakeSnapshotFiles({'a': 'same', 'b': 'same', 'c': 'other'});

      final a = await files.entry(RepoPath('a'));
      final b = await files.entry(RepoPath('b'));
      final c = await files.entry(RepoPath('c'));

      expect(a?.blobId, b?.blobId);
      expect(a?.blobId, isNot(c?.blobId));
      expect(await files.entry(RepoPath('missing')), isNull);
    });

    test('size is the byte length, and null for a missing file', () async {
      final files = FakeSnapshotFiles({'a.txt': 'ação'});

      expect(await files.size(RepoPath('a.txt')), 6);
      expect(await files.size(RepoPath('missing')), isNull);
    });
  });

  group('FakeDocuments', () {
    final files = FakeSnapshotFiles(const {});
    final location = Location.wholeFile(RepoPath('pubspec.yaml'));

    test('returns the canned result for a path', () async {
      final parsed = DocumentParsed(
        LocatedScalar(location: location, value: 1),
      );
      final documents = FakeDocuments({'pubspec.yaml': parsed});

      expect(await documents.yaml(files, RepoPath('pubspec.yaml')), parsed);
      expect(await documents.json(files, RepoPath('pubspec.yaml')), parsed);
    });

    test('reports a path without a canned result as missing', () async {
      const documents = FakeDocuments({});

      expect(
        await documents.yaml(files, RepoPath('other.yaml')),
        isA<DocumentMissing>(),
      );
    });
  });

  group('FakeCheckContext', () {
    test('enables every rule unless a set is given', () {
      final open = FakeCheckContext();
      final restricted = FakeCheckContext(
        enabled: {const RuleId('tests', 'solo')},
      );

      expect(open.isEnabled(const RuleId('tests', 'new-skip')), isTrue);
      expect(restricted.isEnabled(const RuleId('tests', 'solo')), isTrue);
      expect(restricted.isEnabled(const RuleId('tests', 'new-skip')), isFalse);
    });

    test('hands out settings by type', () {
      final context = FakeCheckContext(settings: const [_Settings(7)]);

      expect(context.settings<_Settings>().value, 7);
      expect(context.settings<String>, throwsStateError);
    });

    test('defaults to a pre-commit run over an empty snapshot', () async {
      final context = FakeCheckContext();

      expect(context.entry, EntryKind.preCommit);
      expect(context.changes.isEmpty, isTrue);
      expect(context.base, isNull);
      expect(context.targetBranch, isNull);
      expect(await context.snapshot.list(), isEmpty);
      expect(context.packages.packages, isEmpty);
    });

    test('records that the Dart toolchain was asked for', () {
      final context = FakeCheckContext();

      expect(context.dartAccessed, isFalse);
      expect(() => context.dart, throwsStateError);
      expect(context.dartAccessed, isTrue);
    });

    test('exposes the changes it was given', () {
      final changes = ChangeSet([
        FileChange(path: RepoPath('a.dart'), kind: ChangeKind.added),
      ]);

      expect(FakeCheckContext(changes: changes).changes, same(changes));
    });
  });
}

import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:test/test.dart';

void main() {
  group('FileChange', () {
    test('requires previousPath for a rename', () {
      expect(
        () => FileChange(path: RepoPath('a.dart'), kind: ChangeKind.renamed),
        throwsA(isA<AssertionError>()),
      );
    });

    test('forbids previousPath for any other kind', () {
      expect(
        () => FileChange(
          path: RepoPath('a.dart'),
          kind: ChangeKind.modified,
          previousPath: RepoPath('b.dart'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('is equal when path, kind and previousPath are equal', () {
      FileChange renamed(String from) => FileChange(
        path: RepoPath('new.dart'),
        kind: ChangeKind.renamed,
        previousPath: RepoPath(from),
      );

      expect(renamed('old.dart'), renamed('old.dart'));
      expect(renamed('old.dart').hashCode, renamed('old.dart').hashCode);
      expect(renamed('old.dart'), isNot(renamed('other.dart')));
      expect(
        FileChange(path: RepoPath('a.dart'), kind: ChangeKind.added),
        isNot(FileChange(path: RepoPath('a.dart'), kind: ChangeKind.deleted)),
      );
    });
  });

  group('ChangeSet', () {
    final set = ChangeSet([
      FileChange(path: RepoPath('b.dart'), kind: ChangeKind.deleted),
      FileChange(path: RepoPath('a.dart'), kind: ChangeKind.modified),
      FileChange(
        path: RepoPath('c.dart'),
        kind: ChangeKind.renamed,
        previousPath: RepoPath('old.dart'),
      ),
    ]);

    test('sorts changes by path', () {
      expect(set.changes.map((change) => change.path.value), [
        'a.dart',
        'b.dart',
        'c.dart',
      ]);
    });

    test('present leaves out deleted paths', () {
      expect(set.present.map((change) => change.path.value), [
        'a.dart',
        'c.dart',
      ]);
    });

    test('looks a change up by its path', () {
      expect(set[RepoPath('c.dart')]?.previousPath, RepoPath('old.dart'));
      expect(set[RepoPath('zzz')], isNull);
    });

    test('does not find a rename by its previous path', () {
      expect(set[RepoPath('old.dart')], isNull);
    });

    test('exposes an unmodifiable list', () {
      expect(
        () => set.changes.add(
          FileChange(path: RepoPath('d.dart'), kind: ChangeKind.added),
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects the same path twice', () {
      expect(
        () => ChangeSet([
          FileChange(path: RepoPath('a.dart'), kind: ChangeKind.added),
          FileChange(path: RepoPath('a.dart'), kind: ChangeKind.modified),
        ]),
        throwsArgumentError,
      );
    });

    test('reports emptiness and length', () {
      expect(ChangeSet(const []).isEmpty, isTrue);
      expect(set.isEmpty, isFalse);
      expect(set.length, 3);
    });
  });
}

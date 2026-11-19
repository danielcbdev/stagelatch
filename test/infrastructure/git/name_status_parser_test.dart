import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/git/name_status_parser.dart';
import 'package:test/test.dart';

void main() {
  test('maps status letters and reads both paths of a rename', () {
    final changes = parseNameStatus([
      'A',
      'a.dart',
      'M',
      'b.dart',
      'D',
      'c.dart',
      'R087',
      'old.dart',
      'new.dart',
      'T',
      'd',
    ]);

    expect(changes, [
      FileChange(path: RepoPath('a.dart'), kind: ChangeKind.added),
      FileChange(path: RepoPath('b.dart'), kind: ChangeKind.modified),
      FileChange(path: RepoPath('c.dart'), kind: ChangeKind.deleted),
      FileChange(
        path: RepoPath('new.dart'),
        kind: ChangeKind.renamed,
        previousPath: RepoPath('old.dart'),
      ),
      FileChange(path: RepoPath('d'), kind: ChangeKind.typeChanged),
    ]);
  });

  test('returns nothing for empty output', () {
    expect(parseNameStatus(const []), isEmpty);
  });

  test('treats a copy as an added file at the new path', () {
    expect(parseNameStatus(['C075', 'source.dart', 'copy.dart']), [
      FileChange(path: RepoPath('copy.dart'), kind: ChangeKind.added),
    ]);
  });

  test('keeps paths with spaces, quotes and newlines intact', () {
    final changes = parseNameStatus(['A', 'a "b"\nc.txt']);

    expect(changes.single.path, RepoPath('a "b"\nc.txt'));
  });

  test('an unmerged entry is a usage error', () {
    expect(
      () => parseNameStatus(['U', 'c.txt']),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          'The index has unmerged paths; resolve conflicts first.',
        ),
      ),
    );
  });

  test('an unknown status is an internal error', () {
    expect(
      () => parseNameStatus(['X', 'a.dart']),
      throwsA(
        isA<InternalException>().having(
          (error) => error.message,
          'message',
          'Unexpected status "X" in git diff output.',
        ),
      ),
    );
  });

  test('output that ends in the middle of a record is an internal error', () {
    expect(() => parseNameStatus(['A']), throwsA(isA<InternalException>()));
    expect(
      () => parseNameStatus(['R100', 'old.dart']),
      throwsA(isA<InternalException>()),
    );
  });
}

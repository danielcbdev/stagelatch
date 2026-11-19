import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:test/test.dart';

void main() {
  group('RepoPath', () {
    test('rejects paths that are not clean repository paths', () {
      const invalid = [
        '',
        '/a',
        'a/',
        'a//b',
        './a',
        'a/../b',
        'a/./b',
        'a\u0000b',
        '.',
        '..',
      ];
      for (final value in invalid) {
        expect(
          () => RepoPath(value),
          throwsFormatException,
          reason: '"$value" must be rejected',
        );
      }
    });

    test('keeps backslashes and spaces as ordinary characters', () {
      final path = RepoPath(r'lib/a b\c.dart');

      expect(path.value, r'lib/a b\c.dart');
      expect(path.basename, r'a b\c.dart');
    });

    test('exposes basename, extension, parent and containment', () {
      final path = RepoPath('lib/src/a.g.dart');

      expect(path.basename, 'a.g.dart');
      expect(path.extension, '.dart');
      expect(path.parent, RepoPath('lib/src'));
      expect(RepoPath('a.dart').parent, isNull);
      expect(path.isWithin(RepoPath('lib')), isTrue);
      expect(path.isWithin(RepoPath('lib/src')), isTrue);
      expect(path.isWithin(RepoPath('li')), isFalse);
      expect(path.isWithin(path), isFalse);
    });

    test('has no extension for dotfiles and plain names', () {
      expect(RepoPath('.env').extension, '');
      expect(RepoPath('Makefile').extension, '');
      expect(RepoPath('config/.env.production').extension, '.production');
      expect(RepoPath('a.b/c').extension, '');
    });

    test('orders by code unit, the same on every platform', () {
      final paths = [
        RepoPath('b'),
        RepoPath('B'),
        RepoPath('a/b'),
        RepoPath('a'),
      ]..sort();

      expect(paths.map((path) => path.value), ['B', 'a', 'a/b', 'b']);
    });

    test('is equal to another path with the same value', () {
      expect(RepoPath('lib/a.dart'), RepoPath('lib/a.dart'));
      expect(RepoPath('lib/a.dart').hashCode, RepoPath('lib/a.dart').hashCode);
      expect(RepoPath('lib/a.dart'), isNot(RepoPath('lib/b.dart')));
    });

    test('prints as its value', () {
      expect(RepoPath('lib/a.dart').toString(), 'lib/a.dart');
    });
  });
}

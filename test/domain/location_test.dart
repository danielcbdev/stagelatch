import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:test/test.dart';

void main() {
  group('Position', () {
    test('is 1-based on both axes', () {
      expect(() => Position(0, 1), throwsA(isA<AssertionError>()));
      expect(() => Position(1, 0), throwsA(isA<AssertionError>()));
      expect(const Position(1, 1).line, 1);
    });

    test('orders by line, then column', () {
      final positions = [
        const Position(2, 1),
        const Position(1, 9),
        const Position(1, 2),
      ]..sort();

      expect(positions, const [Position(1, 2), Position(1, 9), Position(2, 1)]);
    });

    test('is equal to another position with the same line and column', () {
      expect(const Position(3, 4), const Position(3, 4));
      expect(const Position(3, 4).hashCode, const Position(3, 4).hashCode);
      expect(const Position(3, 4), isNot(const Position(4, 3)));
    });

    test('prints as line:column', () {
      expect(const Position(14, 5).toString(), '14:5');
    });
  });

  group('Location', () {
    test('is equal to another location with the same path and range', () {
      Location at(String path, int line) =>
          Location(RepoPath(path), Position(line, 1), Position(line, 8));

      expect(at('a.dart', 1), at('a.dart', 1));
      expect(at('a.dart', 1).hashCode, at('a.dart', 1).hashCode);
      expect(at('a.dart', 1), isNot(at('b.dart', 1)));
      expect(at('a.dart', 1), isNot(at('a.dart', 2)));
    });

    test('differs when only the end differs', () {
      final path = RepoPath('a.dart');

      expect(
        Location(path, const Position(1, 1), const Position(1, 2)),
        isNot(Location(path, const Position(1, 1), const Position(1, 3))),
      );
    });

    test('prints as path:line:column of its start', () {
      final location = Location(
        RepoPath('pubspec.yaml'),
        const Position(14, 5),
        const Position(14, 26),
      );

      expect(location.toString(), 'pubspec.yaml:14:5');
    });

    test('wholeFile points at the first character', () {
      final location = Location.wholeFile(RepoPath('android/key.properties'));

      expect(location.start, const Position(1, 1));
      expect(location.end, const Position(1, 1));
    });
  });
}

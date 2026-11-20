import 'package:stagelatch/src/checks/tests/test_key.dart';
import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:test/test.dart';

TestCall _call(String description, {List<String> groups = const []}) =>
    TestCall(
      function: 'test',
      description: description,
      groups: groups,
      location: Location.wholeFile(RepoPath('test/a_test.dart')),
    );

void main() {
  group('testKey', () {
    test('is the groups followed by the description', () {
      expect(
        testKey(_call('adds', groups: ['cart'])),
        testKey(_call('adds', groups: ['cart'])),
      );
      expect(
        testKey(_call('adds', groups: ['cart'])),
        isNot(testKey(_call('adds', groups: ['basket']))),
      );
      expect(
        testKey(_call('adds')),
        isNot(testKey(_call('adds', groups: ['cart']))),
      );
    });

    test('cannot be confused by a separator inside a description', () {
      expect(testKey(_call('b', groups: ['a'])), isNot(testKey(_call('a/b'))));
      expect(
        testKey(_call('c', groups: ['a', 'b'])),
        isNot(testKey(_call('c', groups: ['a b']))),
      );
      expect(
        testKey(_call('c', groups: ['a'])),
        isNot(testKey(_call('', groups: ['a', 'c']))),
      );
    });
  });

  group('isTestFile', () {
    final packages = PackageMap([
      const DartPackage(root: null, name: 'app'),
      DartPackage(root: RepoPath('packages/ui'), name: 'ui'),
    ]);

    bool isTest(String path) => isTestFile(RepoPath(path), packages);

    test('a _test.dart file under test/ of its package', () {
      expect(isTest('test/cart_test.dart'), isTrue);
      expect(isTest('test/cart/cart_test.dart'), isTrue);
      expect(isTest('packages/ui/test/button_test.dart'), isTrue);
    });

    test('a file outside test/ or not ending in _test.dart is not one', () {
      expect(isTest('lib/cart_test.dart'), isFalse);
      expect(isTest('test/cart.dart'), isFalse);
      expect(isTest('test/helpers/matchers.dart'), isFalse);
      expect(isTest('test/cart_test.dart.bak'), isFalse);
      expect(isTest('test/cart_test.txt'), isFalse);
    });

    test('test/ is the one of the package that owns the file', () {
      // `packages/ui/test` belongs to ui; `packages/ui/lib/test/x_test.dart`
      // is not under the package's own `test/`.
      expect(isTest('packages/ui/lib/test/x_test.dart'), isFalse);
      expect(isTest('other/test/x_test.dart'), isFalse);
    });

    test('a path no package owns is not a test file', () {
      final none = PackageMap(const []);

      expect(isTestFile(RepoPath('test/a_test.dart'), none), isFalse);
    });
  });
}

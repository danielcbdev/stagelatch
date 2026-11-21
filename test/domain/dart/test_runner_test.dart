import 'package:stagelatch/src/domain/dart/test_runner.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:test/test.dart';

FailedTest failed({
  String file = 'test/a_test.dart',
  int line = 3,
  int column = 5,
  String name = 'g fails',
}) => FailedTest(file: RepoPath(file), line: line, column: column, name: name);

void main() {
  group('FailedTest', () {
    test('equals another with the same file, position and name', () {
      expect(failed(), failed());
      expect(failed().hashCode, failed().hashCode);
    });

    for (final other in {
      'file': failed(file: 'test/b_test.dart'),
      'line': failed(line: 4),
      'column': failed(column: 6),
      'name': failed(name: 'g passes'),
    }.entries) {
      test('differs when the ${other.key} differs', () {
        expect(failed(), isNot(other.value));
      });
    }
  });

  group('TestRunResult', () {
    test('has no failure and no startup error by default', () {
      const result = TestRunResult();

      expect(result.failures, isEmpty);
      expect(result.startupError, isNull);
    });

    test('equals another with the same failures and startup error', () {
      expect(
        TestRunResult(failures: [failed()], startupError: 'boom'),
        TestRunResult(failures: [failed()], startupError: 'boom'),
      );
      expect(
        TestRunResult(failures: [failed()]).hashCode,
        TestRunResult(failures: [failed()]).hashCode,
      );
    });

    test('differs when the failures or the startup error differ', () {
      expect(
        TestRunResult(failures: [failed()]),
        isNot(TestRunResult(failures: [failed(line: 9)])),
      );
      expect(
        const TestRunResult(startupError: 'a'),
        isNot(const TestRunResult(startupError: 'b')),
      );
      expect(
        const TestRunResult(),
        isNot(const TestRunResult(startupError: 'a')),
      );
    });

    test('merge concatenates failures in order and keeps the first error', () {
      final merged = TestRunResult.merge([
        TestRunResult(failures: [failed(line: 1)]),
        const TestRunResult(startupError: 'first'),
        TestRunResult(failures: [failed(line: 2)], startupError: 'second'),
      ]);

      expect(merged.failures, [failed(line: 1), failed(line: 2)]);
      expect(merged.startupError, 'first');
    });

    test('merging nothing is a clean result', () {
      expect(TestRunResult.merge(const []), const TestRunResult());
    });
  });
}

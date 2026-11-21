import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/domain/dart/test_runner.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/test_event_parser.dart';
import 'package:test/test.dart';

const int _mebibyte = 1024 * 1024;

final _fallback = RepoPath('test/fallback_test.dart');

/// Feeds [lines] to a parser for a repository at [root] and finishes it.
TestRunResult run(
  Iterable<String> lines, {
  int exitCode = 0,
  String standardError = '',
  String root = '/repo',
  p.Context? context,
}) {
  final parser = TestEventParser(
    repoRoot: root,
    fallbackFile: _fallback,
    context: context ?? p.posix,
  );
  lines.forEach(parser.add);
  return parser.finish(exitCode: exitCode, standardError: standardError);
}

/// The lines of a recorded fixture.
List<String> fixture(String name) =>
    File(p.join('test', 'fixtures', 'test_events', name)).readAsLinesSync();

TestRunResult parse(
  String name, {
  int exitCode = 0,
  String standardError = '',
}) => run(fixture(name), exitCode: exitCode, standardError: standardError);

String event(Map<String, Object?> json) => jsonEncode(json);

String suite(int id, String path) => event({
  'type': 'suite',
  'suite': {'id': id, 'platform': 'vm', 'path': path},
});

String testStart(
  int id,
  String name, {
  int suiteId = 0,
  List<int> groups = const [1],
  String? url,
  int? line,
  int? column,
  String? rootUrl,
  int? rootLine,
  int? rootColumn,
}) => event({
  'type': 'testStart',
  'test': {
    'id': id,
    'name': name,
    'suiteID': suiteId,
    'groupIDs': groups,
    'line': line,
    'column': column,
    'url': url,
    'root_url': ?rootUrl,
    'root_line': ?rootLine,
    'root_column': ?rootColumn,
  },
});

String testDone(
  int id,
  String result, {
  bool hidden = false,
  bool skipped = false,
}) => event({
  'type': 'testDone',
  'testID': id,
  'result': result,
  'hidden': hidden,
  'skipped': skipped,
});

String error(int id, String text) =>
    event({'type': 'error', 'testID': id, 'error': text, 'isFailure': true});

/// The events of one failing test at [url], 7:9.
List<String> failingTestAt(
  String url, {
  String? rootUrl,
  int? rootLine,
  int? rootColumn,
}) => [
  testStart(
    3,
    'g fails',
    url: url,
    line: 7,
    column: 9,
    rootUrl: rootUrl,
    rootLine: rootLine,
    rootColumn: rootColumn,
  ),
  error(3, 'Expected: <2>'),
  testDone(3, 'failure'),
];

void main() {
  group('recorded runs', () {
    test('all passing produces no failure and no startup error', () {
      expect(parse('all_pass.jsonl'), const TestRunResult());
    });

    test('a failing test is reported with file, line, column and name', () {
      final result = parse('one_failure.jsonl', exitCode: 1);

      expect(
        result.failures.single,
        FailedTest(
          file: RepoPath('test/b_test.dart'),
          line: 2,
          column: 29,
          name: 'g fails',
        ),
      );
      expect(result.startupError, isNull);
    });

    test('a test with result error is a failure, counted once however many '
        'error events it had', () {
      final result = parse('error_result.jsonl', exitCode: 1);

      expect(result.failures.map((failure) => failure.name), [
        'throws',
        'loading spinner',
      ]);
      expect(result.failures.first.line, 3);
      expect(result.startupError, isNull);
    });

    test('a real failing test named loading spinner is a FailedTest, not a '
        'startup error', () {
      final result = parse('error_result.jsonl', exitCode: 1);

      expect(result.startupError, isNull);
      expect(
        result.failures.last,
        FailedTest(
          file: RepoPath('test/d_test.dart'),
          line: 7,
          column: 3,
          name: 'loading spinner',
        ),
      );
    });

    test('hidden loading tests and skipped tests are not failures', () {
      final result = parse('one_failure.jsonl', exitCode: 1);

      expect(result.failures.map((failure) => failure.name), ['g fails']);
    });

    test(
      'a compile error is a startup error with the first diagnostic line',
      () {
        final result = parse('compile_error.jsonl', exitCode: 1);

        expect(
          result.startupError,
          "test/c_test.dart:2:22: Error: A value of type 'String' can't be "
          "assigned to a variable of type 'int'",
        );
        expect(result.failures, isEmpty);
      },
    );

    test(
      'a test declared through a helper is located at its root location',
      () {
        final result = parse('helper_location.jsonl', exitCode: 1);

        expect(
          result.failures.single,
          FailedTest(
            file: RepoPath('test/e_test.dart'),
            line: 3,
            column: 3,
            name: 'helper declared',
          ),
        );
      },
    );

    test('flutter output with blank lines and a json array is read like '
        'dart output', () {
      final result = parse('flutter_noise.jsonl', exitCode: 1);

      expect(
        result.failures.single,
        FailedTest(
          file: RepoPath('test/w_test.dart'),
          line: 4,
          column: 3,
          name: 'fails',
        ),
      );
      expect(result.startupError, isNull);
    });
  });

  group('lines that are not events', () {
    final failure = failingTestAt('file:///repo/test/a_test.dart');

    test('blank lines, text, arrays and truncated json are ignored', () {
      final result = run([
        '',
        '   ',
        'Running "flutter pub get"...',
        '[{"event":"test.startedProcess","params":{"vmServiceUri":null}}]',
        '{"type":"testStart","test":{"id":9,',
        '"a string"',
        '{"no":"type"}',
        '{"type":5}',
        '[]',
        '42',
        ...failure,
        '',
      ], exitCode: 1);

      expect(result.failures.single.name, 'g fails');
      expect(result.startupError, isNull);
    });

    test('a line longer than 1 MiB is dropped unparsed', () {
      final padded = event({
        'type': 'testDone',
        'testID': 3,
        'result': 'failure',
        'hidden': false,
        'padding': 'x' * _mebibyte,
      });
      expect(padded.length, greaterThan(_mebibyte));
      final lines = [...failingTestAt('file:///repo/test/a_test.dart')]
        ..removeLast()
        ..add(padded);

      final result = run(lines, exitCode: 1);

      expect(result.failures, isEmpty);
      expect(result.startupError, 'the test tool exited with code 1');
    });

    test('a line of exactly 1 MiB is still read', () {
      final done = event({
        'type': 'testDone',
        'testID': 3,
        'result': 'failure',
        'hidden': false,
        'padding': '',
      });
      final padded = event({
        'type': 'testDone',
        'testID': 3,
        'result': 'failure',
        'hidden': false,
        'padding': 'x' * (_mebibyte - done.length),
      });
      expect(padded.length, _mebibyte);
      final lines = [...failingTestAt('file:///repo/test/a_test.dart')]
        ..removeLast()
        ..add(padded);

      expect(run(lines, exitCode: 1).failures, hasLength(1));
    });
  });

  group('startup errors', () {
    test('a file that does not exist uses the only line, without the '
        'trailing dot', () {
      final result = run([
        suite(0, 'test/nope_test.dart'),
        testStart(1, 'loading test/nope_test.dart', groups: const []),
        event({
          'type': 'error',
          'testID': 1,
          'error': 'Failed to load "test/nope_test.dart": Does not exist.',
          'isFailure': false,
        }),
        testDone(1, 'error'),
      ], exitCode: 1);

      expect(
        result.startupError,
        'Failed to load "test/nope_test.dart": Does not exist',
      );
    });

    test('one trailing colon is removed from the chosen line', () {
      final result = run([
        suite(0, 'test/a_test.dart'),
        testStart(1, 'loading test/a_test.dart', groups: const []),
        error(1, 'Failed to load "test/a_test.dart":'),
        testDone(1, 'error'),
      ], exitCode: 1);

      expect(result.startupError, 'Failed to load "test/a_test.dart"');
    });

    test('a flutter loader is recognised by its absolute suite path', () {
      final result = run([
        suite(0, '/repo/test/w_test.dart'),
        testStart(1, 'loading /repo/test/w_test.dart', groups: const []),
        error(
          1,
          'Failed to load "/repo/test/w_test.dart":\nCompilation failed',
        ),
        testDone(1, 'error'),
      ], exitCode: 1);

      expect(result.startupError, 'Compilation failed');
      expect(result.failures, isEmpty);
    });

    test('a loader that failed without any text still names the file', () {
      final result = run([
        suite(0, 'test/a_test.dart'),
        testStart(1, 'loading test/a_test.dart', groups: const []),
        testDone(1, 'error'),
      ], exitCode: 1);

      expect(
        result.startupError,
        'the test tool could not load test/a_test.dart',
      );
    });

    test('a test named like a loader but with a location is a failure', () {
      final result = run([
        suite(0, 'test/a_test.dart'),
        testStart(
          3,
          'loading test/a_test.dart',
          url: 'file:///repo/test/a_test.dart',
          line: 4,
          column: 3,
        ),
        error(3, 'boom'),
        testDone(3, 'failure'),
      ], exitCode: 1);

      expect(result.startupError, isNull);
      expect(result.failures.single.name, 'loading test/a_test.dart');
    });

    test('a test named like a loader inside a group is a failure', () {
      final result = run([
        suite(0, 'test/a_test.dart'),
        testStart(3, 'loading test/a_test.dart'),
        error(3, 'boom'),
        testDone(3, 'failure'),
      ], exitCode: 1);

      expect(result.startupError, isNull);
      expect(result.failures.single.file, _fallback);
    });

    test('a locationless test whose name only starts with loading is a '
        'failure', () {
      final result = run([
        suite(0, 'test/a_test.dart'),
        testStart(3, 'loading spinner', groups: const []),
        error(3, 'boom'),
        testDone(3, 'failure'),
      ], exitCode: 1);

      expect(result.startupError, isNull);
      expect(result.failures.single.name, 'loading spinner');
    });

    test('no event and a non-zero exit takes the first line of standard '
        'error', () {
      final result = run(
        const [],
        exitCode: 64,
        standardError:
            '\n  \nCould not find a file named "pubspec.yaml".\nmore',
      );

      expect(
        result.startupError,
        'Could not find a file named "pubspec.yaml".',
      );
    });

    test('standard error is ignored once a test has started', () {
      final result = run(
        fixture('all_pass.jsonl'),
        exitCode: 3,
        standardError: 'noise\n',
      );

      expect(result.startupError, 'the test tool exited with code 3');
    });

    test('standard error is ignored when the exit code is zero', () {
      expect(run(const [], standardError: 'noise\n'), const TestRunResult());
    });

    test('a non-zero exit with no failure and no error names the exit '
        'code', () {
      final result = run(const [], exitCode: 79);

      expect(result.startupError, 'the test tool exited with code 79');
    });

    test('a failure is enough to explain a non-zero exit', () {
      final result = parse('one_failure.jsonl', exitCode: 1);

      expect(result.startupError, isNull);
    });

    test('the startup error is cut to 300 characters', () {
      final long = 'e' * 500;
      final result = run([
        suite(0, 'test/a_test.dart'),
        testStart(1, 'loading test/a_test.dart', groups: const []),
        error(1, 'Failed to load "test/a_test.dart":\n$long'),
        testDone(1, 'error'),
      ], exitCode: 1);

      expect(result.startupError, hasLength(300));
    });
  });

  group('locations', () {
    test('urls become repository paths from the package', () {
      final result = run(
        failingTestAt('file:///repo/packages/ui/test/a_test.dart'),
        exitCode: 1,
      );

      expect(
        result.failures.single,
        FailedTest(
          file: RepoPath('packages/ui/test/a_test.dart'),
          line: 7,
          column: 9,
          name: 'g fails',
        ),
      );
    });

    test('a url outside the repository falls back to the first file at '
        '1:1', () {
      final result = run(
        failingTestAt('file:///elsewhere/test/a_test.dart'),
        exitCode: 1,
      );

      expect(
        result.failures.single,
        FailedTest(file: _fallback, line: 1, column: 1, name: 'g fails'),
      );
    });

    test('a sibling directory that shares the root prefix is outside', () {
      final result = run(
        failingTestAt('file:///repo2/test/a_test.dart'),
        exitCode: 1,
      );

      expect(result.failures.single.file, _fallback);
    });

    test('a test without a url falls back to the first file at 1:1', () {
      final result = run([
        testStart(3, 'g fails'),
        error(3, 'boom'),
        testDone(3, 'error'),
      ], exitCode: 1);

      expect(
        result.failures.single,
        FailedTest(file: _fallback, line: 1, column: 1, name: 'g fails'),
      );
    });

    test('a url that is not a file url falls back', () {
      final result = run(
        failingTestAt('package:foo/foo_test.dart'),
        exitCode: 1,
      );

      expect(result.failures.single.file, _fallback);
    });

    test('a url that does not parse falls back', () {
      final result = run(failingTestAt('http://[::1'), exitCode: 1);

      expect(result.failures.single.file, _fallback);
    });

    test('a file url that cannot become a path falls back', () {
      final result = run(
        failingTestAt('file:///repo/test/a_test.dart#fragment'),
        exitCode: 1,
      );

      expect(result.failures.single.file, _fallback);
    });

    test('the root location wins over the url', () {
      final result = run(
        failingTestAt(
          'file:///repo/test/helper.dart',
          rootUrl: 'file:///repo/test/e_test.dart',
          rootLine: 2,
          rootColumn: 4,
        ),
        exitCode: 1,
      );

      expect(
        result.failures.single,
        FailedTest(
          file: RepoPath('test/e_test.dart'),
          line: 2,
          column: 4,
          name: 'g fails',
        ),
      );
    });

    test('a root url outside the repository does not fall back to the '
        'helper', () {
      final result = run(
        failingTestAt(
          'file:///repo/test/helper.dart',
          rootUrl: 'file:///elsewhere/e_test.dart',
          rootLine: 2,
          rootColumn: 4,
        ),
        exitCode: 1,
      );

      expect(result.failures.single.file, _fallback);
    });

    test('failures are ordered by file, line, column and name, whatever '
        'order the suites finished in', () {
      final lines = [
        testStart(3, 'z', url: 'file:///repo/test/b_test.dart', line: 1),
        testDone(3, 'failure'),
        testStart(4, 'y', url: 'file:///repo/test/a_test.dart', line: 9),
        testDone(4, 'failure'),
        testStart(5, 'x', url: 'file:///repo/test/a_test.dart', line: 2),
        testDone(5, 'failure'),
      ];

      final result = run(lines, exitCode: 1);

      expect(result.failures.map((failure) => failure.name), ['x', 'y', 'z']);
    });

    test('Windows urls and roots are handled', () {
      final result = run(
        failingTestAt('file:///C:/repo/test/a_test.dart'),
        exitCode: 1,
        root: r'C:\repo',
        context: p.windows,
      );

      expect(result.failures.single.file, RepoPath('test/a_test.dart'));
    });

    test('a Windows drive letter is compared without case', () {
      final result = run(
        failingTestAt('file:///c:/repo/test/a_test.dart'),
        exitCode: 1,
        root: r'C:\repo',
        context: p.windows,
      );

      expect(result.failures.single.file, RepoPath('test/a_test.dart'));
    });

    test('a url on another Windows drive falls back', () {
      final result = run(
        failingTestAt('file:///D:/repo/test/a_test.dart'),
        exitCode: 1,
        root: r'C:\repo',
        context: p.windows,
      );

      expect(result.failures.single.file, _fallback);
    });
  });
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/domain/dart/test_runner.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/process_test_runner.dart';
import 'package:test/test.dart';

import '../../support/fake_process.dart';
import '../../support/fixture_package.dart';

/// One call of the fake starter.
typedef Start = ({
  String executable,
  List<String> arguments,
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
});

/// A starter that hands out [processes] in order and records each call in
/// [calls].
ProcessStarter fakeStarter(List<FakeProcess> processes, List<Start> calls) {
  Future<Process> starter(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    calls.add((
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
    ));
    return processes[calls.length - 1];
  }

  return starter;
}

ResolvedSdk sdk({
  String dart = '/sdk/bin/dart',
  String? flutter = '/flutter/bin/flutter',
}) => ResolvedSdk(
  root: '/sdk',
  dartExecutable: dart,
  flutterExecutable: flutter,
  version: '3.13.4',
  source: SdkSource.path,
);

DartPackage dartPackage({String? root}) =>
    DartPackage(root: root == null ? null : RepoPath(root), name: 'app');

DartPackage flutterPackage({String? root}) => DartPackage(
  root: root == null ? null : RepoPath(root),
  name: 'app',
  usesFlutter: true,
);

List<RepoPath> paths(List<String> values) => [
  for (final value in values) RepoPath(value),
];

/// 300 paths whose arguments need two batches.
List<String> manyFiles() => [
  for (var i = 0; i < 300; i++)
    'test/${i.toString().padLeft(4, '0')}_${'x' * 80}.dart',
];

/// The events of one failing test at `file:///repo/test/<file>.dart` 2:3.
List<String> failingEvents({String name = 'fails', String file = 'a_test'}) {
  final start =
      '{"type":"testStart","test":{"id":3,"name":"$name","suiteID":0,'
      '"groupIDs":[1],"line":2,"column":3,'
      '"url":"file:///repo/test/$file.dart"}}';
  return [
    '{"type":"suite","suite":{"id":0,"platform":"vm","path":"test/$file.dart"}}',
    start,
    '{"type":"error","testID":3,"error":"boom","isFailure":true}',
    '{"type":"testDone","testID":3,"result":"failure","hidden":false}',
  ];
}

ProcessTestRunner runnerFor(
  List<FakeProcess> processes, {
  ResolvedSdk? resolved,
  String repoRoot = '/repo',
  bool isWindows = false,
  List<Start>? calls,
  Duration? killGrace,
  TestLineConsumer? consumeLine,
}) => ProcessTestRunner(
  sdk: resolved ?? sdk(),
  repoRoot: repoRoot,
  starter: fakeStarter(processes, calls ?? []),
  isWindows: isWindows,
  killGrace: killGrace,
  consumeLine: consumeLine,
);

void main() {
  group('startup refusals', () {
    test('a Flutter package without a flutter executable is a startup error '
        'and starts nothing', () async {
      final calls = <Start>[];
      final runner = runnerFor(
        const [],
        resolved: sdk(flutter: null),
        calls: calls,
      );

      final result = await runner.run(
        flutterPackage(),
        paths(['test/a_test.dart']),
      );

      expect(
        result,
        const TestRunResult(
          startupError: 'the resolved SDK has no flutter executable',
        ),
      );
      expect(calls, isEmpty);
    });

    for (final executable in [
      r'C:\flutter\bin\flutter.bat',
      r'C:\flutter\bin\FLUTTER.CMD',
    ]) {
      for (final unsafe in [
        '"',
        '&',
        '|',
        '<',
        '>',
        '^',
        '%',
        '!',
        '\n',
        '\u0001',
        '\u007f',
      ]) {
        test('on Windows $executable refuses a test path with code unit '
            '${unsafe.codeUnitAt(0)} and starts nothing', () async {
          final calls = <Start>[];
          final runner = runnerFor(
            const [],
            resolved: sdk(flutter: executable),
            repoRoot: r'C:\repo',
            isWindows: true,
            calls: calls,
          );

          final result = await runner.run(
            flutterPackage(),
            paths(['test/a${unsafe}b_test.dart']),
          );

          expect(
            result,
            TestRunResult(
              startupError: 'unsafe test path: test/a${unsafe}b_test.dart',
            ),
          );
          expect(calls, isEmpty);
        });
      }
    }

    test('on Windows an unsafe path in a later batch still starts '
        'nothing', () async {
      final calls = <Start>[];
      final runner = runnerFor(
        const [],
        resolved: sdk(flutter: r'C:\flutter\bin\flutter.bat'),
        repoRoot: r'C:\repo',
        isWindows: true,
        calls: calls,
      );

      final result = await runner.run(
        flutterPackage(),
        paths([...manyFiles(), 'test/zzz&_test.dart']),
      );

      expect(result.startupError, 'unsafe test path: test/zzz&_test.dart');
      expect(calls, isEmpty);
    });

    test('on Windows a .bat executable accepts a path with a space', () async {
      final calls = <Start>[];
      final runner = runnerFor(
        [FakeProcess()],
        resolved: sdk(flutter: r'C:\flutter\bin\flutter.bat'),
        repoRoot: r'C:\repo',
        isWindows: true,
        calls: calls,
      );

      await runner.run(flutterPackage(), paths(['test/a b_test.dart']));

      expect(calls.single.arguments.last, 'test/a b_test.dart');
    });

    test('off Windows a .bat executable is not special', () async {
      final calls = <Start>[];
      final runner = runnerFor(
        [FakeProcess()],
        resolved: sdk(flutter: '/odd/flutter.bat'),
        calls: calls,
      );

      await runner.run(flutterPackage(), paths(['test/a&b_test.dart']));

      expect(calls, hasLength(1));
    });

    test('on Windows the dart executable is not special', () async {
      final calls = <Start>[];
      final runner = runnerFor(
        [FakeProcess()],
        resolved: sdk(dart: r'C:\sdk\bin\dart.exe'),
        repoRoot: r'C:\repo',
        isWindows: true,
        calls: calls,
      );

      await runner.run(dartPackage(), paths(['test/a&b_test.dart']));

      expect(calls, hasLength(1));
    });

    test('no file starts nothing', () async {
      final calls = <Start>[];
      final runner = runnerFor(const [], calls: calls);

      expect(await runner.run(dartPackage(), const []), const TestRunResult());
      expect(calls, isEmpty);
    });
  });

  group('the process', () {
    test('the environment is inherited unchanged, no shell is used and stdin '
        'is closed', () async {
      final child = FakeProcess();
      final calls = <Start>[];
      final runner = runnerFor([child], calls: calls);

      await runner.run(
        dartPackage(root: 'packages/ui'),
        paths(['packages/ui/test/a_test.dart']),
      );

      final start = calls.single;
      expect(start.executable, '/sdk/bin/dart');
      expect(start.arguments, [
        '--suppress-analytics',
        'test',
        '--reporter',
        'json',
        '--',
        'test/a_test.dart',
      ]);
      expect(start.workingDirectory, p.posix.join('/repo', 'packages', 'ui'));
      expect(start.environment, isNull);
      expect(start.includeParentEnvironment, isTrue);
      expect(start.runInShell, isFalse);
      expect(child.stdinClosed, isTrue);
      expect(child.killed, isFalse);
    });

    test('a package at the repository root runs in the repository '
        'root', () async {
      final calls = <Start>[];
      final runner = runnerFor([FakeProcess()], calls: calls);

      await runner.run(dartPackage(), paths(['test/a_test.dart']));

      expect(calls.single.workingDirectory, '/repo');
    });

    test(
      'a failing test is reported with its path in the repository',
      () async {
        final runner = runnerFor([
          FakeProcess(stdoutLines: failingEvents(), exitCodeValue: 1),
        ]);

        final result = await runner.run(
          dartPackage(),
          paths(['test/a_test.dart']),
        );

        expect(
          result.failures.single,
          FailedTest(
            file: RepoPath('test/a_test.dart'),
            line: 2,
            column: 3,
            name: 'fails',
          ),
        );
      },
    );

    test('a location outside the repository falls back to the first file '
        'of the batch', () async {
      final runner = runnerFor([
        FakeProcess(
          stdoutLines: [
            for (final line in failingEvents(file: 'x'))
              line.replaceAll('/repo/', '/elsewhere/'),
          ],
          exitCodeValue: 1,
        ),
      ]);

      final result = await runner.run(
        dartPackage(root: 'packages/ui'),
        paths(['packages/ui/test/b_test.dart', 'packages/ui/test/a_test.dart']),
      );

      expect(
        result.failures.single.file,
        RepoPath('packages/ui/test/a_test.dart'),
      );
      expect(result.failures.single.line, 1);
    });

    test('the repository root is resolved through symlinks', () async {
      final base = await Directory.systemTemp.createTemp('stagelatch_link_');
      addTearDown(() => base.delete(recursive: true));
      final real = Directory(p.join(base.path, 'real'))..createSync();
      final link = Link(p.join(base.path, 'link'))..createSync(real.path);
      final resolved = await real.resolveSymbolicLinks();
      final calls = <Start>[];
      final runner = runnerFor(
        [
          FakeProcess(
            stdoutLines: [
              for (final line in failingEvents())
                line.replaceAll('file:///repo', Uri.file(resolved).toString()),
            ],
            exitCodeValue: 1,
          ),
        ],
        repoRoot: link.path,
        calls: calls,
      );

      final result = await runner.run(
        dartPackage(),
        paths(['test/a_test.dart']),
      );

      expect(result.failures.single.file, RepoPath('test/a_test.dart'));
      expect(result.failures.single.line, 2);
      expect(calls.single.workingDirectory, resolved);
    }, skip: Platform.isWindows ? 'symlinks need privileges on Windows' : null);

    test('standard error is bounded to its first 64 KiB', () async {
      final runner = runnerFor([
        FakeProcess(
          standardError: '${'\n' * (64 * 1024)}late line\n',
          exitCodeValue: 64,
        ),
      ]);

      final result = await runner.run(
        dartPackage(),
        paths(['test/a_test.dart']),
      );

      expect(result.startupError, 'the test tool exited with code 64');
    });

    test('standard error within the bound explains a run with no '
        'event', () async {
      final runner = runnerFor([
        FakeProcess(standardError: 'No tests were found.\n', exitCodeValue: 79),
      ]);

      final result = await runner.run(
        dartPackage(),
        paths(['test/a_test.dart']),
      );

      expect(result.startupError, 'No tests were found.');
    });

    test('the child is killed and awaited when the stream throws', () async {
      final child = FakeProcess(
        stdoutLines: const ['{"type":"start"}'],
        stdoutError: StateError('pipe broke'),
        hangsUntilKilled: true,
      );
      final runner = runnerFor([child]);

      await expectLater(
        runner.run(dartPackage(), paths(['test/a_test.dart'])),
        throwsA(isA<StateError>()),
      );

      expect(child.killed, isTrue);
      expect(child.signals, [ProcessSignal.sigterm]);
      await expectLater(child.exitCode, completes);
    });

    test('the child is killed and awaited when the parser throws', () async {
      final child = FakeProcess(
        stdoutLines: const ['{"type":"start"}'],
        hangsUntilKilled: true,
      );
      final runner = runnerFor(
        [child],
        consumeLine: (parser, line) {
          parser.add(line);
          throw StateError('parser broke');
        },
      );

      await expectLater(
        runner.run(dartPackage(), paths(['test/a_test.dart'])),
        throwsA(isA<StateError>()),
      );

      expect(child.killed, isTrue);
      expect(child.signals, [ProcessSignal.sigterm]);
      await expectLater(child.exitCode, completes);
    });

    test('a child that ignores SIGTERM is killed with SIGKILL', () async {
      final child = FakeProcess(
        stdoutLines: const ['{"type":"start"}'],
        stdoutError: StateError('pipe broke'),
        hangsUntilKilled: true,
        ignoredKills: 1,
      );
      final runner = runnerFor([
        child,
      ], killGrace: const Duration(milliseconds: 30));

      await expectLater(
        runner.run(dartPackage(), paths(['test/a_test.dart'])),
        throwsA(isA<StateError>()),
      );

      expect(child.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
      await expectLater(child.exitCode, completes);
    });

    test('a child that has exited is not killed', () async {
      final child = FakeProcess(stdoutLines: failingEvents(), exitCodeValue: 1);
      final runner = runnerFor([child]);

      await runner.run(dartPackage(), paths(['test/a_test.dart']));

      expect(child.killed, isFalse);
    });

    test('a process that cannot be started is a startup error, not an '
        'exception', () async {
      Future<Process> starter(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
        Map<String, String>? environment,
        bool includeParentEnvironment = true,
        bool runInShell = false,
        ProcessStartMode mode = ProcessStartMode.normal,
      }) => Future.error(
        ProcessException(executable, arguments, 'No such file or directory', 2),
      );
      final runner = ProcessTestRunner(
        sdk: sdk(),
        repoRoot: '/repo',
        starter: starter,
      );

      final result = await runner.run(
        dartPackage(),
        paths(['test/a_test.dart']),
      );

      expect(
        result.startupError,
        'cannot start /sdk/bin/dart: No such file or directory',
      );
    });

    test('batches of one package run in order and their results are '
        'merged', () async {
      final files = manyFiles();
      final calls = <Start>[];
      final runner = runnerFor([
        FakeProcess(
          stdoutLines: failingEvents(name: 'first'),
          exitCodeValue: 1,
        ),
        FakeProcess(
          stdoutLines: failingEvents(name: 'second', file: 'b_test'),
          exitCodeValue: 1,
        ),
      ], calls: calls);

      final result = await runner.run(
        dartPackage(),
        paths(files.reversed.toList()),
      );

      expect(calls, hasLength(2));
      expect([for (final call in calls) ...call.arguments.skip(5)], files);
      expect(result.failures.map((failure) => failure.name), [
        'first',
        'second',
      ]);
    });

    test('the first startup error of the batches is kept', () async {
      final runner = runnerFor([
        FakeProcess(exitCodeValue: 5),
        FakeProcess(exitCodeValue: 6),
      ]);

      final result = await runner.run(dartPackage(), paths(manyFiles()));

      expect(result.startupError, 'the test tool exited with code 5');
    });
  });

  group('the factory', () {
    test('creates a runner for the sdk and the repository', () {
      final runner = const ProcessTestRunnerFactory().create(
        sdk: sdk(),
        repoRoot: '/repo',
      );

      expect(runner, isA<ProcessTestRunner>());
    });
  });

  group('the fixture package', () {
    late String root;
    late ResolvedSdk realSdk;

    setUpAll(() {
      final dart = Platform.resolvedExecutable;
      realSdk = ResolvedSdk(
        root: p.dirname(p.dirname(dart)),
        dartExecutable: dart,
        flutterExecutable: null,
        version: Platform.version.split(' ').first,
        source: SdkSource.path,
      );
    });

    setUp(() async {
      root = await copyFixturePackage(withTestPackage: true);
      // Written at run time, so the repository holds no *_test.dart that
      // this repository's own `tests/affected` would select.
      await writeFile(root, 'test/a_test.dart', '''
import 'package:test/test.dart';

void main() {
  test('adds', () => expect(1 + 1, 2));
  test('breaks', () => expect(1, 2));
}
''');
      await writeFile(root, 'test/b_test.dart', '''
import 'package:test/test.dart';

void main() {
  test('adds', () => expect(1 + 1, 2));
}
''');
      await writeFile(root, 'test/c_test.dart', '''
import 'package:test/test.dart';

void main() {int x = 'text'; print(x);}
''');
    });

    tearDown(() => Directory(root).delete(recursive: true));

    test('one failing test is found end to end', () async {
      final runner = ProcessTestRunner(sdk: realSdk, repoRoot: root);

      final result = await runner.run(
        const DartPackage(root: null, name: 'dart_app'),
        paths(['test/a_test.dart', 'test/b_test.dart']),
      );

      expect(result.startupError, isNull);
      expect(
        result.failures.single,
        FailedTest(
          file: RepoPath('test/a_test.dart'),
          line: 5,
          column: 3,
          name: 'breaks',
        ),
      );
    });

    test('a compile error is a startup error', () async {
      final runner = ProcessTestRunner(sdk: realSdk, repoRoot: root);

      final result = await runner.run(
        const DartPackage(root: null, name: 'dart_app'),
        paths(['test/c_test.dart']),
      );

      expect(result.failures, isEmpty);
      expect(
        result.startupError,
        "test/c_test.dart:3:22: Error: A value of type 'String' can't be "
        "assigned to a variable of type 'int'",
      );
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/infrastructure/custom/spawned_check_process.dart';
import 'package:test/test.dart';

import '../../support/fake_process.dart';

/// Facts for gate: callers=dart test only; glob=0; synthetic FakeProcess +
/// fixtures; user: "Test: test/infrastructure/custom/spawned_check_process_test.dart".

typedef Start = ({
  String executable,
  List<String> arguments,
  String? workingDirectory,
  bool runInShell,
});

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

void main() {
  group('SpawnedCheckProcessFactory resolution', () {
    test('replaces dart with the resolved SDK binary', () async {
      final calls = <Start>[];
      final factory = SpawnedCheckProcessFactory(
        repoRoot: '/repo',
        sdk: sdk(),
        starter: fakeStarter([FakeProcess()], calls),
        isWindows: false,
        pathEnv: '/usr/bin',
      );

      await factory.start(const [
        'dart',
        'tool/check.dart',
      ], workingDirectory: '/repo');

      expect(calls.single.executable, '/sdk/bin/dart');
      expect(calls.single.arguments, ['tool/check.dart']);
      expect(calls.single.runInShell, isFalse);
      expect(calls.single.workingDirectory, '/repo');
    });

    test('replaces flutter with the resolved SDK binary', () async {
      final calls = <Start>[];
      final factory = SpawnedCheckProcessFactory(
        repoRoot: '/repo',
        sdk: sdk(),
        starter: fakeStarter([FakeProcess()], calls),
        isWindows: false,
      );

      await factory.start(const [
        'flutter',
        'pub',
        'run',
        'x',
      ], workingDirectory: '/repo');

      expect(calls.single.executable, '/flutter/bin/flutter');
    });

    test('a missing bare PATH name fails before start', () async {
      final calls = <Start>[];
      // Avoid /usr/bin: CI hosts often ship python there.
      final factory = SpawnedCheckProcessFactory(
        repoRoot: '/repo',
        starter: fakeStarter([FakeProcess()], calls),
        isWindows: false,
        pathEnv: '/stagelatch-no-such-path:/also-missing-bin',
        context: p.posix,
      );

      expect(
        () => factory.start(const ['python'], workingDirectory: '/repo'),
        throwsA(
          isA<InternalException>().having(
            (e) => e.message,
            'message',
            contains('not found on PATH'),
          ),
        ),
      );
      expect(calls, isEmpty);
    });

    test('a bare PATH hit is started by absolute path', () async {
      final bin = await Directory.systemTemp.createTemp('sl-path-');
      addTearDown(() => bin.delete(recursive: true));
      // Windows needs a PATHEXT suffix and ';' PATH separators; a bare
      // `tool` file with isWindows:false splits `C:\...` on ':' and misses.
      final toolName = Platform.isWindows ? 'tool.bat' : 'tool';
      final executable = File(p.join(bin.path, toolName));
      if (Platform.isWindows) {
        await executable.writeAsString('@echo off\r\n');
      } else {
        await executable.writeAsString('#!/bin/sh\n');
      }
      final calls = <Start>[];
      final repoRoot = Platform.isWindows ? r'C:\repo' : '/repo';
      final factory = SpawnedCheckProcessFactory(
        repoRoot: repoRoot,
        starter: fakeStarter([FakeProcess()], calls),
        isWindows: Platform.isWindows,
        pathEnv: bin.path,
        pathExt: Platform.isWindows ? '.BAT;.CMD;.EXE' : null,
        context: p.context,
      );

      await factory.start(const ['tool'], workingDirectory: repoRoot);

      expect(calls, hasLength(1));
      expect(p.isAbsolute(calls.single.executable), isTrue);
      expect(
        File(calls.single.executable).resolveSymbolicLinksSync(),
        executable.resolveSymbolicLinksSync(),
      );
      expect(calls.single.runInShell, isFalse);
    });

    test('on Windows refuses batch metacharacters in arguments', () async {
      final calls = <Start>[];
      final factory = SpawnedCheckProcessFactory(
        repoRoot: r'C:\repo',
        starter: fakeStarter([FakeProcess()], calls),
        isWindows: true,
        context: p.windows,
      );

      expect(
        () => factory.start(const [
          r'C:\tools\check.bat',
          'a&b',
        ], workingDirectory: r'C:\repo'),
        throwsA(
          isA<InternalException>().having(
            (e) => e.message,
            'message',
            contains('unsafe argument'),
          ),
        ),
      );
      expect(calls, isEmpty);
    });

    test('never uses a shell', () async {
      final calls = <Start>[];
      final factory = SpawnedCheckProcessFactory(
        repoRoot: '/repo',
        sdk: sdk(),
        starter: fakeStarter([FakeProcess()], calls),
        isWindows: false,
      );

      await factory.start(const ['dart', 'x.dart'], workingDirectory: '/repo');
      expect(calls.single.runInShell, isFalse);
    });
  });

  group('SpawnedCheckProcess lifecycle', () {
    test('kill stops a hanging child', () async {
      final child = FakeProcess(hangsUntilKilled: true);
      final factory = SpawnedCheckProcessFactory(
        repoRoot: '/repo',
        sdk: sdk(),
        starter: fakeStarter([child], []),
        isWindows: false,
        killGrace: const Duration(milliseconds: 30),
      );

      final process = await factory.start(const [
        'dart',
        'hang.dart',
      ], workingDirectory: '/repo');
      await process.kill();
      expect(child.killed, isTrue);
      expect(await process.exitCode, isNegative);
    });

    test('send writes a line and closeStdin closes stdin', () async {
      final child = FakeProcess(stdoutLines: const ['{"type":"done"}']);
      final factory = SpawnedCheckProcessFactory(
        repoRoot: '/repo',
        sdk: sdk(),
        starter: fakeStarter([child], []),
        isWindows: false,
      );

      final process = await factory.start(const [
        'dart',
        'x.dart',
      ], workingDirectory: '/repo');
      process.send('{"type":"init"}');
      await process.closeStdin();
      expect(child.stdinClosed, isTrue);
      await process.kill();
    });

    test('standardError keeps only the first 64 KiB', () async {
      final oversized = 'x' * (maxCustomCheckStandardError + 2048);
      final child = FakeProcess(
        stdoutLines: const ['{"type":"done"}'],
        standardError: oversized,
      );
      final factory = SpawnedCheckProcessFactory(
        repoRoot: '/repo',
        sdk: sdk(),
        starter: fakeStarter([child], []),
        isWindows: false,
      );

      final process = await factory.start(const [
        'dart',
        'x.dart',
      ], workingDirectory: '/repo');
      final stderr = await process.standardError;
      expect(stderr.length, maxCustomCheckStandardError);
      await process.kill();
    });
  });

  group('real fixture children', () {
    test('well_behaved speaks protocol lines on stdout', () async {
      final script = p.join(
        'test',
        'fixtures',
        'custom_checks',
        'well_behaved.dart',
      );
      final process = await Process.start(Platform.resolvedExecutable, [
        script,
      ]);
      final linesFuture = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      process.stdin.writeln(
        '{"type":"init","protocol":1,"entry":"ci","settings":{},'
        '"capabilities":[]}',
      );
      process.stdin.writeln('{"type":"run","changes":[],"all":false}');
      await process.stdin.close();
      final collected = await linesFuture;
      expect(collected.any((line) => line.contains('"type":"ready"')), isTrue);
      expect(
        collected.any((line) => line.contains('"type":"finding"')),
        isTrue,
      );
      expect(collected.last, contains('"type":"done"'));
      expect(await process.exitCode, 0);
    });

    test('noisy fixture prints a stray line before ready', () async {
      final script = p.join('test', 'fixtures', 'custom_checks', 'noisy.dart');
      final process = await Process.start(Platform.resolvedExecutable, [
        script,
      ]);
      final linesFuture = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      process.stdin.writeln(
        '{"type":"init","protocol":1,"entry":"ci","settings":{},'
        '"capabilities":[]}',
      );
      await process.stdin.close();
      final collected = await linesFuture;
      expect(collected.first, 'stray print from the child');
      expect(await process.exitCode, 0);
    });
  });
}

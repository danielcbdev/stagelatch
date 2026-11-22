@Tags(['git', 'e2e'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/custom_checks.dart';
import '../support/temp_repo.dart';

/// AC-36: a bare `run[0]` is resolved by walking `PATH`, skipping every
/// directory inside the repository, and started by absolute path. An
/// executable planted at the repository root is never run, even when the
/// root itself is on `PATH`, and even on Windows, where the OS would
/// otherwise search the process's current directory first.
///
/// The CLI runs as a real process, because the resolver reads the `PATH`
/// of the process it runs in.
void main() {
  const name = 'stagelatch-planted-probe';
  late TempRepo repo;
  late Directory scratch;

  setUp(() async {
    repo = await TempRepo.create();
    scratch = await Directory.systemTemp.createTemp('stagelatch-ac36-');
  });

  tearDown(() async {
    await repo.dispose();
    await scratch.delete(recursive: true);
  });

  test('an executable planted at the root is not run', () async {
    final marker = p.join(scratch.path, 'ran.txt');
    if (Platform.isWindows) {
      await repo.write('$name.bat', '@echo off\r\necho ran> "$marker"\r\n');
    } else {
      await repo.write(name, '#!/bin/sh\necho ran > "$marker"\n');
      await Process.run('chmod', ['755', p.join(repo.root, name)]);
    }
    await repo.write('tool/keep.dart', 'void main() {}\n');
    await commitCustomCheckSetup(
      repo,
      customCheckConfig(run: const [name], sources: const ['tool/keep.dart']),
    );
    await repo.stageContent('lib/a.dart', 'void a() {}\n// changed\n');

    final separator = Platform.isWindows ? ';' : ':';
    final environment = {
      for (final MapEntry(:key, :value) in repo.environment.entries)
        if (key.toUpperCase() != 'PATH') key: value,
      'PATH': '${repo.root}$separator${Platform.environment['PATH'] ?? ''}',
    };
    final result = await Process.run(
      Platform.resolvedExecutable,
      [p.absolute('bin', 'stagelatch.dart'), 'run', 'pre-commit'],
      workingDirectory: repo.root,
      environment: environment,
      includeParentEnvironment: false,
    );

    expect(result.exitCode, 70, reason: '${result.stdout}${result.stderr}');
    expect(
      result.stderr as String,
      contains('custom check "probe": cannot start'),
    );
    expect(File(marker).existsSync(), isFalse);
  });
}

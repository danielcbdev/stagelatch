@Tags(['git'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/temp_repo.dart';

/// AC-34: the reference check under `example/custom_check/` speaks protocol 1
/// end to end against the real host (init/ready/run/done; optional finding).
void main() {
  TempRepo? repo;
  late Directory exampleSrc;

  setUp(() async {
    exampleSrc = Directory(p.join('example', 'custom_check'));
    expect(
      exampleSrc.existsSync(),
      isTrue,
      reason: 'example/custom_check/ must exist for AC-34',
    );

    final created = await TempRepo.create();
    repo = created;
    await _copyExampleInto(created, exampleSrc);
    await _pubGetExample(created);

    await created.write('lib/a.dart', 'void hello() {}\n');
    await created.write('stagelatch.yaml', '''
hooks:
  pre-commit: [example]
  pre-push: [example]
custom_checks:
  example:
    run: [dart, run, example/custom_check/bin/check.dart]
    sources:
      - example/custom_check/bin/check.dart
      - example/custom_check/lib/no_print.dart
      - example/custom_check/pubspec.yaml
    rules:
      no-print: error
''');
    await created.stage('example');
    await created.stage('lib/a.dart');
    await created.stage('stagelatch.yaml');
    await created.commit('wire example custom check');
  });

  tearDown(() async {
    await repo?.dispose();
  });

  test('example check reports example/no-print through the host', () async {
    final active = repo!;
    await active.write('lib/a.dart', 'void hello() {\n  print("hi");\n}\n');
    await active.stage('lib/a.dart');

    final result = await active.stagelatch([
      'run',
      'pre-commit',
      '--reporter',
      'json',
    ]);

    expect(result.exitCode, 1, reason: result.stdout + result.stderr);
    final json = jsonDecode(result.stdout) as Map<String, Object?>;
    final findings = json['findings']! as List<Object?>;
    expect(findings, isNotEmpty);
    final finding = findings.first! as Map<String, Object?>;
    expect(finding['rule'], 'example/no-print');
    expect(finding['path'], 'lib/a.dart');
    expect(finding['message'], contains('print'));
  });

  test('example check passes when no print call is present', () async {
    final active = repo!;
    await active.write('lib/b.dart', 'void other() {}\n');
    await active.stage('lib/b.dart');

    final result = await active.stagelatch([
      'run',
      'pre-commit',
      '--reporter',
      'json',
    ]);

    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    final json = jsonDecode(result.stdout) as Map<String, Object?>;
    final findings = json['findings']! as List<Object?>;
    expect(findings, isEmpty);
  });
}

Future<void> _copyExampleInto(TempRepo repo, Directory source) async {
  final destRoot = p.join(repo.root, 'example', 'custom_check');
  await for (final entity in source.list(recursive: true)) {
    final relative = p.relative(entity.path, from: source.path);
    if (relative == '.dart_tool' ||
        relative.startsWith('.dart_tool${p.separator}') ||
        relative == 'pubspec.lock') {
      continue;
    }
    final dest = p.join(destRoot, relative);
    if (entity is Directory) {
      await Directory(dest).create(recursive: true);
    } else if (entity is File) {
      await File(dest).parent.create(recursive: true);
      await entity.copy(dest);
    }
  }
}

Future<void> _pubGetExample(TempRepo repo) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    const ['pub', 'get'],
    workingDirectory: p.join(repo.root, 'example', 'custom_check'),
    environment: repo.environment,
    includeParentEnvironment: false,
  );
  final stderr = await process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;
  expect(code, 0, reason: stderr);
}

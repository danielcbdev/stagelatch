@Tags(['git'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/infrastructure/custom/spawned_check_process.dart';
import 'package:test/test.dart';

import '../support/temp_repo.dart';

/// AC-34: the reference check under `example/custom_check/` speaks protocol 1
/// end to end against the real host (init/ready/run/done; optional finding).
///
/// Spawn path matches the well_behaved fixture: `dart <file.dart>` (no
/// `dart run`). The temp copy flattens `bin/check.dart` + `lib/no_print.dart`
/// into one script so Windows CI does not need `pub get` / package_config
/// and does not hang on a cold multi-package `dart run`. TearDown kills
/// leftover children (taskkill tree on Windows).
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
    await _flattenExampleEntry(created);

    await created.write('lib/a.dart', 'void hello() {}\n');
    await created.write('stagelatch.yaml', '''
hooks:
  pre-commit: [example]
  pre-push: [example]
custom_checks:
  example:
    run: [dart, example/custom_check/bin/check.dart]
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
    // ExternalCheck kills in finally; if the test timed out first, the child
    // may still hold files under the temp repo
    // (PathAccessException on Windows).
    await SpawnedCheckProcess.killAllActive();
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

/// Inlines `lib/no_print.dart` into `bin/check.dart` so `dart <file>` works
/// without a package_config (same spawn shape as well_behaved on Windows).
Future<void> _flattenExampleEntry(TempRepo repo) async {
  final root = p.join(repo.root, 'example', 'custom_check');
  final entry = File(p.join(root, 'bin', 'check.dart'));
  final rule = await File(p.join(root, 'lib', 'no_print.dart')).readAsString();
  // Drop the library directive; it cannot sit after the entry's imports.
  final ruleBody = rule.replaceFirst(
    RegExp(r'^library;\s*', multiLine: true),
    '',
  );
  final script = await entry.readAsString();
  const packageImport = "import 'package:example_custom_check/no_print.dart';";
  expect(
    script.contains(packageImport),
    isTrue,
    reason: 'example bin/check.dart must import the rule package',
  );
  await entry.writeAsString(script.replaceFirst(packageImport, ruleBody));
}

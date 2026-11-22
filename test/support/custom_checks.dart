/// Shared setup for the custom check acceptance scenarios (AC-29 to AC-36).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'temp_repo.dart';

/// Copies `test/fixtures/custom_checks/<fixture>.dart` into [repo] at
/// `tool/check.dart`, the path every scenario's config names.
Future<void> addFixtureCheck(TempRepo repo, String fixture) async {
  final source = File(
    p.join('test', 'fixtures', 'custom_checks', '$fixture.dart'),
  );
  await repo.write('tool/check.dart', await source.readAsString());
}

/// The `stagelatch.yaml` of a repository whose only check is the custom
/// check [id], listed on both git hooks so `ci` selects it too.
///
/// [run] and [sources] are written as JSON strings, which YAML reads as
/// they are, so arguments with shell metacharacters stay intact. [rules]
/// maps rule names (without the `<id>/` prefix) to a level.
String customCheckConfig({
  String id = 'probe',
  List<String> run = const ['dart', 'tool/check.dart'],
  List<String> sources = const ['tool/check.dart'],
  Map<String, String> rules = const {},
  String? timeout,
}) {
  final buffer = StringBuffer()
    ..writeln('hooks:')
    ..writeln('  pre-commit: [$id]')
    ..writeln('  pre-push: [$id]')
    ..writeln('custom_checks:')
    ..writeln('  $id:')
    ..writeln('    run: ${jsonEncode(run)}')
    ..writeln('    sources: ${jsonEncode(sources)}');
  if (timeout != null) buffer.writeln('    timeout: $timeout');
  if (rules.isNotEmpty) {
    buffer.writeln('    rules:');
    for (final MapEntry(:key, :value) in rules.entries) {
      buffer.writeln('      $key: $value');
    }
  }
  return buffer.toString();
}

/// Commits [config], the check at `tool/check.dart` (when present) and a
/// clean `lib/a.dart`, so the next staged change is the only one.
Future<void> commitCustomCheckSetup(TempRepo repo, String config) async {
  await repo.write('stagelatch.yaml', config);
  await repo.write('lib/a.dart', 'void a() {}\n');
  await repo.stage('.');
  await repo.commit('wire the custom check');
}

/// Whether the process [pid] is still running, without signalling it.
Future<bool> processIsAlive(int pid) async {
  if (Platform.isWindows) {
    final result = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
    return (result.stdout as String).contains(' $pid ');
  }
  final result = await Process.run('kill', ['-0', '$pid']);
  return result.exitCode == 0;
}

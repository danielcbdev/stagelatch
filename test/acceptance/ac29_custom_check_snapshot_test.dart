@Tags(['git'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:stagelatch/src/infrastructure/custom/spawned_check_process.dart';
import 'package:test/test.dart';

import '../support/custom_checks.dart';
import '../support/temp_repo.dart';

/// AC-29: a well-behaved custom check completes the handshake, reads files
/// only through `read`, and therefore sees the snapshot, never the working
/// tree. Its finding carries its own rule id, and the exit code follows the
/// configured level.
void main() {
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
    await addFixtureCheck(repo, 'snapshot_reader');
  });

  tearDown(() async {
    await SpawnedCheckProcess.killAllActive();
    await repo.dispose();
  });

  Future<(int, List<Map<String, Object?>>)> runPreCommit() async {
    final result = await repo.stagelatch([
      'run',
      'pre-commit',
      '--reporter',
      'json',
    ]);
    final json = jsonDecode(result.stdout) as Map<String, Object?>;
    final findings = (json['findings']! as List<Object?>)
        .cast<Map<String, Object?>>();
    return (result.exitCode, findings);
  }

  test('a marker that is staged but not on disk is found', () async {
    await commitCustomCheckSetup(repo, customCheckConfig());
    await repo.stageContent('lib/a.dart', 'void a() {}\n// FORBIDDEN\n');

    final (code, findings) = await runPreCommit();

    expect(code, 1);
    expect(findings, hasLength(1));
    expect(findings.single['rule'], 'probe/forbidden');
    expect(findings.single['severity'], 'error');
    expect(findings.single['path'], 'lib/a.dart');
    expect(findings.single['line'], 2);
  });

  test('a marker that is on disk but not staged is not seen', () async {
    await commitCustomCheckSetup(repo, customCheckConfig());
    await repo.stageContent('lib/a.dart', 'void a() {}\n// clean\n');
    await repo.write('lib/a.dart', 'void a() {}\n// FORBIDDEN\n');

    final (code, findings) = await runPreCommit();

    expect(code, 0);
    expect(findings, isEmpty);
  });

  test(
    'a warning level reports the finding and lets the commit pass',
    () async {
      await commitCustomCheckSetup(
        repo,
        customCheckConfig(rules: const {'forbidden': 'warning'}),
      );
      await repo.stageContent('lib/a.dart', 'void a() {}\n// FORBIDDEN\n');

      final (code, findings) = await runPreCommit();

      expect(code, 0);
      expect(findings.single['rule'], 'probe/forbidden');
      expect(findings.single['severity'], 'warning');
    },
  );
}

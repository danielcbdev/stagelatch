@Tags(['git'])
@Timeout(Duration(minutes: 2))
library;

import 'package:stagelatch/src/infrastructure/custom/spawned_check_process.dart';
import 'package:test/test.dart';

import '../support/custom_checks.dart';
import '../support/temp_repo.dart';

/// AC-35: when the check's own source differs from the snapshot, the check
/// is not started and the run ends with exit 64 and the pre-commit text of
/// `custom-checks.md` section 6. Once the same source is staged, the check
/// runs again and reports what it finds.
void main() {
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
    await addFixtureCheck(repo, 'snapshot_reader');
    await commitCustomCheckSetup(repo, customCheckConfig());
    await repo.stageContent('lib/a.dart', 'void a() {}\n// FORBIDDEN\n');
  });

  tearDown(() async {
    await SpawnedCheckProcess.killAllActive();
    await repo.dispose();
  });

  test('an unstaged edit to the check blocks with exit 64', () async {
    final source = await repo.read('tool/check.dart');
    await repo.write('tool/check.dart', '$source// local edit\n');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 64, reason: result.stdout + result.stderr);
    expect(
      result.stderr,
      contains(
        'custom check "probe": source diverges from the snapshot at '
        'tool/check.dart. Stage the check source changes, or pass '
        '--no-custom-checks.',
      ),
    );
    expect(result.stdout, isNot(contains('probe/forbidden')));
  });

  test('once the edit is staged the check runs again', () async {
    final source = await repo.read('tool/check.dart');
    await repo.write('tool/check.dart', '$source// local edit\n');
    await repo.stage('tool/check.dart');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 1, reason: result.stdout + result.stderr);
    expect(result.stdout, contains('probe/forbidden'));
  });
}

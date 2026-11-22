@Tags(['git'])
@Timeout(Duration(minutes: 2))
library;

import 'package:stagelatch/src/infrastructure/custom/spawned_check_process.dart';
import 'package:test/test.dart';

import '../support/custom_checks.dart';
import '../support/temp_repo.dart';

/// AC-30: a custom check that breaks the protocol never passes silently. A
/// stray line on stdout, a finding for a rule it did not declare and a
/// finding whose path leaves the repository each end the run with exit 70,
/// naming the check, and no finding of that check is reported.
void main() {
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
  });

  tearDown(() async {
    await SpawnedCheckProcess.killAllActive();
    await repo.dispose();
  });

  for (final fixture in ['noisy', 'lying', 'outside_path']) {
    test('$fixture: exit 70 naming the check', () async {
      await addFixtureCheck(repo, fixture);
      await commitCustomCheckSetup(repo, customCheckConfig(id: 'fixture'));
      await repo.stageContent('lib/a.dart', 'void a() {}\n// changed\n');

      final result = await repo.stagelatch(['run', 'pre-commit']);

      expect(result.exitCode, 70, reason: result.stdout + result.stderr);
      expect(result.stderr, contains('custom check "fixture"'));
      expect(result.stdout, isNot(contains('fixture/')));
    });
  }
}

@Tags(['git'])
@Timeout(Duration(minutes: 2))
library;

import 'package:stagelatch/src/infrastructure/custom/spawned_check_process.dart';
import 'package:test/test.dart';

import '../support/custom_checks.dart';
import '../support/temp_repo.dart';

/// AC-32: `--no-custom-checks` skips every custom check on `run` and `ci`
/// and says so. The check under test never answers, so starting it would
/// end in a timeout with exit 70; passing proves no child was started.
void main() {
  const notice = 'Skipping custom checks (--no-custom-checks).';
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
    await addFixtureCheck(repo, 'hanging');
    await commitCustomCheckSetup(repo, customCheckConfig(timeout: '20s'));
  });

  tearDown(() async {
    await SpawnedCheckProcess.killAllActive();
    await repo.dispose();
  });

  test('run pre-commit skips the check with a notice', () async {
    await repo.stageContent('lib/a.dart', 'void a() {}\n// changed\n');

    final result = await repo.stagelatch([
      'run',
      'pre-commit',
      '--no-custom-checks',
    ]);

    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    expect(result.stdout + result.stderr, contains(notice));
  });

  test('ci skips the check with a notice', () async {
    await repo.git(['checkout', '-b', 'feature']);
    await repo.write('lib/a.dart', 'void a() {}\n// changed\n');
    await repo.stage('lib/a.dart');
    await repo.commit('change a');

    final result = await repo.stagelatch([
      'ci',
      '--base',
      'main',
      '--no-custom-checks',
    ]);

    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    expect(result.stdout + result.stderr, contains(notice));
  });
}

@Tags(['git'])
@TestOn('windows')
@Timeout(Duration(minutes: 2))
library;

import 'package:stagelatch/src/infrastructure/custom/spawned_check_process.dart';
import 'package:test/test.dart';

import '../support/custom_checks.dart';
import '../support/temp_repo.dart';

/// AC-33: on Windows a batch file is run by `cmd.exe`, which reinterprets
/// its arguments, so a `.bat` or `.cmd` check with a metacharacter in an
/// argument is refused before it starts: exit 70 naming the check and the
/// argument. The happy path on every OS is AC-29.
void main() {
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
    await repo.write('tool/marker.txt', 'never written by the check\n');
  });

  tearDown(() async {
    await SpawnedCheckProcess.killAllActive();
    await repo.dispose();
  });

  for (final script in ['tool/check.bat', 'tool/check.cmd']) {
    test('$script with "a&b" is refused', () async {
      await repo.write(script, '@echo off\r\necho ran> tool\\marker.txt\r\n');
      await commitCustomCheckSetup(
        repo,
        customCheckConfig(run: [script, 'a&b'], sources: [script]),
      );
      await repo.stageContent('lib/a.dart', 'void a() {}\n// changed\n');

      final result = await repo.stagelatch(['run', 'pre-commit']);

      expect(result.exitCode, 70, reason: result.stdout + result.stderr);
      expect(result.stderr, contains('custom check "probe"'));
      expect(result.stderr, contains('a&b'));
      expect(
        await repo.read('tool/marker.txt'),
        'never written by the check\n',
      );
    });
  }
}

import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  test('a staged binary file is not a finding', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.writeBytes('icon.bin', [0, 1, 2, 0, 255]);
    await repo.stage('icon.bin');

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 0,
      stdout: cleanReport(1),
    );
  });
}

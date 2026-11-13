import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  test('deleting a pubspec that had a finding is allowed', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.write('pubspec.yaml', badPubspec);
    await repo.stage('pubspec.yaml');
    await repo.commit('add a violating pubspec');
    await repo.git(['rm', 'pubspec.yaml']);

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 0,
      stdout: cleanReport(1),
    );
  });
}

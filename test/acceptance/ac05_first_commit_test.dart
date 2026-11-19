import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  test('the first commit is judged, and a violation blocks it', () async {
    final repo = await TempRepo.create(initialCommit: false);
    addTearDown(repo.dispose);
    await repo.write('pubspec.yaml', badPubspec);
    await repo.stage('pubspec.yaml');

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 1,
      stdout: blockedReport(1),
    );
  });
}

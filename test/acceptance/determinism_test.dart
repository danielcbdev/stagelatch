import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  test(
    'two runs of the same commit agree once durations are removed',
    () async {
      final repo = await TempRepo.create();
      addTearDown(repo.dispose);
      await repo.stageContent('pubspec.yaml', badPubspec);

      final first = await repo.stagelatch(['run', 'pre-commit']);
      final second = await repo.stagelatch(['run', 'pre-commit']);

      expect(first.exitCode, 1);
      expect(stabilize(first.stdout), stabilize(second.stdout));
      expect(stabilize(first.stdout), blockedReport(1));
    },
  );
}

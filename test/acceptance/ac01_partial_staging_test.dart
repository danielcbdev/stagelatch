import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
  });

  tearDown(() => repo.dispose());

  test('a clean index passes when the working tree copy violates', () async {
    await repo.stageContent('pubspec.yaml', cleanPubspec);
    await repo.write('pubspec.yaml', badPubspec);

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 0,
      stdout: cleanReport(1),
    );
  });

  test('a violating index fails when the working tree copy is clean', () async {
    await repo.stageContent('pubspec.yaml', badPubspec);
    await repo.write('pubspec.yaml', cleanPubspec);

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 1,
      stdout: blockedReport(1),
    );
  });
}

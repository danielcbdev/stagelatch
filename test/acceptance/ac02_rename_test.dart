import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
  });

  tearDown(() => repo.dispose());

  test('a rename without a content change is allowed', () async {
    await repo.git(['mv', 'README.md', 'notes.md']);

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 0,
      stdout: cleanReport(1),
    );
  });

  test('a rename that also changes the content is allowed', () async {
    await repo.git(['mv', 'README.md', 'notes.md']);
    await repo.write('notes.md', 'renamed and edited\n');
    await repo.stage('notes.md');

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 0,
      stdout: cleanReport(2),
    );
  });
}

import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  test('paths with a space, a quote and non-ASCII characters pass', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.stageContent('a b.txt', 'space');
    await repo.stageContent('q"uote.txt', 'quote');
    await repo.stageContent('ação.txt', 'accent');

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 0,
      stdout: cleanReport(3),
    );
  });

  test('a path with a newline passes', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.stageContent('new\nline.txt', 'newline');

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 0,
      stdout: cleanReport(1),
    );
  }, testOn: '!windows');
}

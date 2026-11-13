import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  test('the staged config wins over the working tree copy', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.stageContent(
      'stagelatch.yaml',
      'rules:\n  pubspec/path-dependency: off\n',
    );
    await repo.write(
      'stagelatch.yaml',
      'rules:\n  pubspec/path-dependency: error\n',
    );
    await repo.stageContent('pubspec.yaml', badPubspec);

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 0,
      stdout: cleanReport(2),
    );
  });

  test('an unstaged off does not silence a staged error', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.stageContent('stagelatch.yaml', 'min_version: 0.1.0-dev.1\n');
    await repo.write(
      'stagelatch.yaml',
      'rules:\n  pubspec/path-dependency: off\n',
    );
    await repo.stageContent('pubspec.yaml', badPubspec);

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 1,
      stdout: blockedReport(2),
    );
  });
}

import 'package:test/test.dart';

import '../support/temp_repo.dart';

void main() {
  test('commands finish without a prompt and without color', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);

    final version = await repo.stagelatch(['--version']);
    final run = await repo.stagelatch(['run', 'pre-commit']);
    final init = await repo.stagelatch(['init']);
    final install = await repo.stagelatch(['install']);
    final uninstall = await repo.stagelatch(['uninstall']);

    for (final result in [version, run, init, install, uninstall]) {
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, isNot(contains('\u001b')));
      expect(result.stderr, isNot(contains('\u001b')));
    }
    expect(version.stdout, 'stagelatch 0.1.0-dev.1\n');
  });
}

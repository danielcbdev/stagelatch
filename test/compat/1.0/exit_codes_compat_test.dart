import 'package:stagelatch/src/cli/exit_codes.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

void main() {
  test('ExitCode enum freezes 0, 1, 64, 70, 78', () {
    expect(ExitCode.pass.code, 0);
    expect(ExitCode.findings.code, 1);
    expect(ExitCode.usage.code, 64);
    expect(ExitCode.internal.code, 70);
    expect(ExitCode.config.code, 78);
  });

  test('CLI fixtures assert pass, findings and usage exit codes', () async {
    final clean = await TempRepo.create();
    addTearDown(clean.dispose);
    await clean.write('stagelatch.yaml', 'hooks:\n  pre-commit: []\n');
    await clean.stage('stagelatch.yaml');
    expect((await clean.stagelatch(['run', 'pre-commit'])).exitCode, 0);

    final blocked = await TempRepo.create();
    addTearDown(blocked.dispose);
    await blocked.write(
      'pubspec.yaml',
      'name: app\nenvironment:\n  sdk: ^3.0.0\n'
          'dependencies:\n  design_system:\n    path: ../design_system\n',
    );
    await blocked.write('stagelatch.yaml', 'hooks:\n  pre-commit: [pubspec]\n');
    await blocked.stage('pubspec.yaml');
    await blocked.stage('stagelatch.yaml');
    expect((await blocked.stagelatch(['run', 'pre-commit'])).exitCode, 1);

    final usage = await TempRepo.create();
    addTearDown(usage.dispose);
    expect((await usage.stagelatch(['run', 'nope'])).exitCode, 64);
  }, tags: ['git']);
}

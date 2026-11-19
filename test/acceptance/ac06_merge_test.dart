import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  test('a violation merged in unchanged does not block', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.write('pubspec.yaml', cleanPubspec);
    await repo.stage('pubspec.yaml');
    await repo.commit('clean pubspec');
    await repo.git(['switch', '--quiet', '-c', 'feature']);
    await repo.write('pubspec.yaml', badPubspec);
    await repo.stage('pubspec.yaml');
    await repo.commit('violating pubspec');
    await repo.git(['switch', '--quiet', 'main']);
    await repo.write('README.md', 'main moved on\n');
    await repo.stage('README.md');
    await repo.commit('main moves');
    await repo.git(['merge', '--no-ff', '--no-commit', 'feature']);

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 0,
      stdout: cleanReport(0),
    );
  });

  test('editing the merged pubspec during resolution blocks', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.write('pubspec.yaml', cleanPubspec);
    await repo.stage('pubspec.yaml');
    await repo.commit('clean pubspec');
    await repo.git(['switch', '--quiet', '-c', 'feature']);
    await repo.write('pubspec.yaml', 'name: feature\n');
    await repo.stage('pubspec.yaml');
    await repo.commit('feature pubspec');
    await repo.git(['switch', '--quiet', 'main']);
    await repo.write('pubspec.yaml', 'name: main\n');
    await repo.stage('pubspec.yaml');
    await repo.commit('main pubspec');
    await repo.git(['merge', 'feature'], okExitCodes: {1});
    await repo.write('pubspec.yaml', badPubspec);
    await repo.stage('pubspec.yaml');

    expectRun(
      await repo.stagelatch(['run', 'pre-commit']),
      exitCode: 1,
      stdout: blockedReport(1),
    );
  });
}

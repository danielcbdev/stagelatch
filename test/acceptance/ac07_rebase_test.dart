import 'package:test/test.dart';

import '../support/temp_repo.dart';

void main() {
  test('an unmerged rebase index is a usage error', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.write('c.txt', 'base\n');
    await repo.stage('c.txt');
    await repo.commit('c');
    await repo.git(['switch', '--quiet', '-c', 'feature']);
    await repo.write('c.txt', 'feature\n');
    await repo.stage('c.txt');
    await repo.commit('feature c');
    await repo.git(['switch', '--quiet', 'main']);
    await repo.write('c.txt', 'main\n');
    await repo.stage('c.txt');
    await repo.commit('main c');
    await repo.git(['switch', '--quiet', 'feature']);
    await repo.git(['rebase', 'main'], okExitCodes: {1});

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains('The index has unmerged paths; resolve conflicts first.'),
    );
    expect(result.stdout, isEmpty);
    expect(result.stderr, isNot(contains('\u001b')));
  });
}

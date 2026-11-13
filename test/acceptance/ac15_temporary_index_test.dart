import 'dart:io';

import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/shim.dart';
import '../support/temp_repo.dart';

void main() {
  late TempRepo repo;
  late String shim;
  late String before;

  setUp(() async {
    repo = await TempRepo.create();
    await repo.write('pubspec.yaml', cleanPubspec);
    await repo.stage('pubspec.yaml');
    await repo.commit('clean pubspec');
    await repo.stagelatch(['install']);
    await repo.write('pubspec.yaml', badPubspec);
    shim = await createShimDirectory();
    before = (await repo.git(['rev-parse', 'HEAD'])).trim();
  });

  tearDown(() async {
    await Directory(shim).delete(recursive: true);
    await repo.dispose();
  });

  test('git commit -a sees the temporary index and blocks', () async {
    final committed = await runGit(
      repo,
      ['commit', '-a', '-m', 'should be blocked'],
      env: {'PATH': pathWithShim(shim)},
    );
    final after = (await repo.git(['rev-parse', 'HEAD'])).trim();

    expect(committed.code, isNot(0), reason: committed.stderr);
    expect(after, before);
    expect(committed.stdout + committed.stderr, contains('Commit blocked'));
  });

  test('git commit of a path sees the temporary index and blocks', () async {
    final committed = await runGit(
      repo,
      ['commit', '-m', 'should be blocked', '--', 'pubspec.yaml'],
      env: {'PATH': pathWithShim(shim)},
    );
    final after = (await repo.git(['rev-parse', 'HEAD'])).trim();

    expect(committed.code, isNot(0), reason: committed.stderr);
    expect(after, before);
    expect(committed.stdout + committed.stderr, contains('Commit blocked'));
  });
}

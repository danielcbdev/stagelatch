import 'dart:io';

import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/shim.dart';
import '../support/temp_repo.dart';

void main() {
  test(
    'a real git commit runs the hook and does not create the commit',
    () async {
      final repo = await TempRepo.create();
      addTearDown(repo.dispose);
      await repo.stagelatch(['install']);
      await repo.write('pubspec.yaml', badPubspec);
      await repo.stage('pubspec.yaml');
      final shim = await createShimDirectory();
      addTearDown(() => Directory(shim).delete(recursive: true));
      final before = (await repo.git(['rev-parse', 'HEAD'])).trim();

      final committed = await runGit(
        repo,
        ['commit', '-m', 'should be blocked'],
        env: {'PATH': pathWithShim(shim)},
      );
      final after = (await repo.git(['rev-parse', 'HEAD'])).trim();

      expect(committed.code, isNot(0), reason: committed.stderr);
      expect(after, before);
      expect(committed.stdout + committed.stderr, contains('Commit blocked'));
    },
  );
}

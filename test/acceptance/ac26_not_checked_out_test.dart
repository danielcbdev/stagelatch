@Tags(['git'])
library;

import 'package:test/test.dart';

import '../support/affected_repo.dart';
import '../support/temp_repo.dart';

/// AC-26: a pre-push of a branch that is not checked out. The snapshot is
/// the pushed commit and the working tree is another one, so the closure
/// diverges: the tests are skipped with the warning, and the push goes on
/// (ADR-0018, "Pre-push of a branch that is not checked out").
void main() {
  late TempRepo repo;

  tearDown(() async => await repo.dispose());

  test(
    'the push of another branch skips the tests and is not failed',
    () async {
      repo = await createAffectedRepo();
      final base = await sha(repo, 'HEAD');
      await repo.git(['switch', '--quiet', '-c', 'feature']);
      // This commit would fail the test, if it were run.
      final feature = await commitChange(repo, 'lib/a.dart', libraryBroken);
      await repo.git(['switch', '--quiet', 'main']);

      final result = await repo.stagelatch([
        'run',
        'pre-push',
      ], stdin: pushOf('feature', feature, base));

      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
      expect(result.stdout, contains(skipWarning(1)));
      expect(result.stdout, isNot(contains('Test failed')));
      expect(result.stdout, isNot(contains('Push blocked')));
      expect(result.stdout, contains('0 errors, 1 warning'));
    },
  );

  test('the push of the checked-out branch runs the tests', () async {
    repo = await createAffectedRepo();
    final base = await sha(repo, 'HEAD');
    final head = await commitChange(repo, 'lib/a.dart', libraryBroken);

    final result = await repo.stagelatch([
      'run',
      'pre-push',
    ], stdin: pushOf('main', head, base));

    expect(result.exitCode, 1, reason: result.stdout + result.stderr);
    expect(result.stdout, contains('Test failed: one is one.'));
  });

  test('a detached checkout of the pushed commit runs the tests', () async {
    repo = await createAffectedRepo();
    final base = await sha(repo, 'HEAD');
    await repo.git(['switch', '--quiet', '-c', 'feature']);
    final feature = await commitChange(repo, 'lib/a.dart', libraryBroken);
    await repo.git(['switch', '--quiet', '--detach', feature]);

    final result = await repo.stagelatch([
      'run',
      'pre-push',
    ], stdin: pushOf('feature', feature, base));

    expect(result.exitCode, 1, reason: result.stdout + result.stderr);
    expect(result.stdout, contains('Test failed: one is one.'));
  });
}

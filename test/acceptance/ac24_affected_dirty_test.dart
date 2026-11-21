@Tags(['git'])
library;

import 'package:test/test.dart';

import '../support/affected_repo.dart';
import '../support/temp_repo.dart';

/// AC-24: `tests/affected` runs the tests a pushed commit affects, and skips
/// them, with one warning, when a file they execute has uncommitted changes
/// (ADR-0018).
void main() {
  late TempRepo repo;
  late String pushed;
  late String remote;

  Future<void> setUpRepo() async {
    repo = await createAffectedRepo();
    remote = await sha(repo, 'HEAD');
    pushed = await commitChange(repo, 'lib/a.dart', libraryBroken);
  }

  tearDown(() async => await repo.dispose());

  test(
    'a pushed commit that breaks a test is blocked with the failure',
    () async {
      await setUpRepo();

      final result = await repo.stagelatch([
        'run',
        'pre-push',
      ], stdin: pushOf('main', pushed, remote));

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('Test failed: one is one.'));
      expect(result.stdout, contains('test/a_test.dart:5:'));
      expect(result.stdout, contains('Push blocked.'));
    },
  );

  test('the same push while the test file has an unstaged edit is allowed '
      'with the warning', () async {
    await setUpRepo();
    await editUnstaged(repo, 'test/a_test.dart');

    final result = await repo.stagelatch([
      'run',
      'pre-push',
    ], stdin: pushOf('main', pushed, remote));

    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    expect(result.stdout, contains(skipWarning(1)));
    expect(result.stdout, isNot(contains('Test failed')));
    expect(result.stdout, contains('0 errors, 1 warning'));
  });

  test('every divergent file of the closure is counted, changed by the push '
      'or not', () async {
    await setUpRepo();
    await editUnstaged(repo, 'test/a_test.dart');
    await editUnstaged(repo, 'lib/a.dart');

    final result = await repo.stagelatch([
      'run',
      'pre-push',
    ], stdin: pushOf('main', pushed, remote));

    expect(result.exitCode, 0, reason: result.stdout);
    expect(result.stdout, contains(skipWarning(2)));
  });

  test('an unstaged edit outside the closure does not skip', () async {
    await setUpRepo();
    await repo.write('README.md', 'edited\n');

    final result = await repo.stagelatch([
      'run',
      'pre-push',
    ], stdin: pushOf('main', pushed, remote));

    expect(result.exitCode, 1, reason: result.stdout + result.stderr);
    expect(result.stdout, contains('Test failed: one is one.'));
  });

  test('a change no test depends on starts nothing', () async {
    repo = await createAffectedRepo(
      files: {'lib/unused.dart': 'int unused() => 0;\n'},
    );
    remote = await sha(repo, 'HEAD');
    pushed = await commitChange(
      repo,
      'lib/unused.dart',
      'int unused() => 1;\n',
    );
    // A divergent file would skip, if the rule asked at all.
    await editUnstaged(repo, 'test/a_test.dart');

    final result = await repo.stagelatch([
      'run',
      'pre-push',
    ], stdin: pushOf('main', pushed, remote));

    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    expect(result.stdout, isNot(contains('Affected tests were not run')));
  });

  test('ci --all selects every test', () async {
    repo = await createAffectedRepo(files: {'test/b_test.dart': alwaysFailing});

    // Nothing changed against the base: no test is affected.
    final plain = await repo.stagelatch(['ci', '--base', 'HEAD']);
    expect(plain.exitCode, 0, reason: plain.stdout + plain.stderr);

    // --all makes every file changed, so every test is.
    final all = await repo.stagelatch(['ci', '--base', 'HEAD', '--all']);
    expect(all.exitCode, 1, reason: all.stdout + all.stderr);
    expect(all.stdout, contains('Test failed: never passes.'));
    expect(all.stdout, isNot(contains('Test failed: one is one.')));
  });

  test('analyze and tests/affected listed together both run', () async {
    repo = await createAffectedRepo(
      files: {
        'stagelatch.yaml':
            'hooks:\n  pre-commit: []\n  pre-push: [analyze, tests/affected]\n',
      },
    );
    remote = await sha(repo, 'HEAD');
    pushed = await commitChange(repo, 'lib/a.dart', libraryBroken);

    final result = await repo.stagelatch([
      'run',
      'pre-push',
    ], stdin: pushOf('main', pushed, remote));

    expect(result.exitCode, 1, reason: result.stdout + result.stderr);
    expect(result.stdout, contains('Test failed: one is one.'));
    expect(result.stdout, contains('analyze'));
  });
}

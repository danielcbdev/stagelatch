@Tags(['git'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/affected_repo.dart';
import '../support/temp_repo.dart';

/// Makes `.dart_tool/package_config.json` newer than every file of the
/// package, as it is right after `dart pub get`, so that `dart test` does not
/// resolve again and rewrite the lock the test is about.
///
/// Sets the mtime explicitly: on filesystems with 1 s resolution, rewriting
/// the file right after a lock edit can leave both with the same stamp, and
/// pub then rewrites a committed lock that the post-run divergence check
/// must still see as equal to the snapshot.
Future<void> _markResolved(TempRepo repo) async {
  final file = File(p.join(repo.root, '.dart_tool', 'package_config.json'));
  await file.setLastModified(
    DateTime.now().toUtc().add(const Duration(seconds: 2)),
  );
}

/// AC-27: `tests/affected` and the configuration of a package (ADR-0018,
/// hole 3 and the limitations).
void main() {
  late TempRepo repo;
  late String remote;

  Future<String> pushBrokenLibrary() async =>
      await commitChange(repo, 'lib/a.dart', libraryBroken);

  Future<CliResult> push(String pushed) => repo.stagelatch([
    'run',
    'pre-push',
  ], stdin: pushOf('main', pushed, remote));

  tearDown(() async => await repo.dispose());

  group('a change selects every test of the package', () {
    test('analysis_options.yaml', () async {
      repo = await createAffectedRepo(
        files: {
          'analysis_options.yaml': 'linter:\n  rules: []\n',
          'test/b_test.dart': alwaysFailing,
        },
      );
      remote = await sha(repo, 'HEAD');
      final pushed = await commitChange(
        repo,
        'analysis_options.yaml',
        'linter:\n  rules:\n    - camel_case_types\n',
      );

      final result = await push(pushed);

      // test/b_test.dart imports nothing the push changed.
      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('Test failed: never passes.'));
    });

    test('a committed pubspec.lock', () async {
      repo = await createAffectedRepo(
        commitLock: true,
        files: {'test/b_test.dart': alwaysFailing},
      );
      final lock = await repo.read('pubspec.lock');
      // A non-canonical lock as the remote tip. `dart test` rewrites such a
      // file, so the pushed commit must hold the canonical form: otherwise
      // the post-run divergence check of ADR-0018 would discard the results.
      await commitChange(repo, 'pubspec.lock', '$lock\n');
      remote = await sha(repo, 'HEAD');
      final pushed = await commitChange(repo, 'pubspec.lock', lock);
      await _markResolved(repo);

      final result = await push(pushed);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('Test failed: never passes.'));
    });

    test('pubspec.yaml', () async {
      repo = await createAffectedRepo(
        files: {'test/b_test.dart': alwaysFailing},
      );
      remote = await sha(repo, 'HEAD');
      final pubspec = await repo.read('pubspec.yaml');
      final pushed = await commitChange(
        repo,
        'pubspec.yaml',
        '$pubspec# a comment\n',
      );
      await _markResolved(repo);

      final result = await push(pushed);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('Test failed: never passes.'));
    });
  });

  group('the run is skipped', () {
    test('after an unstaged edit to a committed pubspec.lock', () async {
      repo = await createAffectedRepo(commitLock: true);
      remote = await sha(repo, 'HEAD');
      final pushed = await pushBrokenLibrary();
      await editUnstaged(repo, 'pubspec.lock');

      final result = await push(pushed);

      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
      expect(result.stdout, contains(skipWarning(1)));
      expect(result.stdout, contains('pubspec.lock'));
      expect(result.stdout, isNot(contains('Test failed')));
    });

    test('with an untracked, non-ignored analysis_options.yaml', () async {
      repo = await createAffectedRepo();
      remote = await sha(repo, 'HEAD');
      final pushed = await pushBrokenLibrary();
      await repo.write('analysis_options.yaml', 'linter:\n  rules: []\n');

      final result = await push(pushed);

      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
      expect(result.stdout, contains(skipWarning(1)));
      expect(result.stdout, contains('analysis_options.yaml'));
    });

    test('after an unstaged edit to the pubspec.yaml', () async {
      repo = await createAffectedRepo();
      remote = await sha(repo, 'HEAD');
      final pushed = await pushBrokenLibrary();
      await editUnstaged(repo, 'pubspec.yaml');

      final result = await push(pushed);

      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
      expect(result.stdout, contains(skipWarning(1)));
    });
  });

  group('the tests run', () {
    test('with a gitignored pubspec.lock present only on disk', () async {
      repo = await createAffectedRepo(gitignore: '.dart_tool/\npubspec.lock\n');
      remote = await sha(repo, 'HEAD');
      final pushed = await pushBrokenLibrary();
      expect(File(p.join(repo.root, 'pubspec.lock')).existsSync(), isTrue);

      final result = await push(pushed);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('Test failed: one is one.'));
      expect(result.stdout, isNot(contains('Affected tests were not run')));
    });

    test('with a pubspec.lock that was never committed or ignored', () async {
      repo = await createAffectedRepo();
      remote = await sha(repo, 'HEAD');
      final pushed = await pushBrokenLibrary();

      final result = await push(pushed);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('Test failed: one is one.'));
    });

    test('after an unstaged edit to a fixture, dart_test.yaml or build.yaml '
        'alone', () async {
      repo = await createAffectedRepo(
        files: {
          'test/fixtures/data.txt': 'data\n',
          'dart_test.yaml': 'concurrency: 1\n',
          'build.yaml': 'targets: {}\n',
        },
      );
      remote = await sha(repo, 'HEAD');
      final pushed = await pushBrokenLibrary();
      await repo.write('test/fixtures/data.txt', 'edited\n');
      await repo.write('dart_test.yaml', 'concurrency: 2\n');
      await repo.write('build.yaml', 'targets: {default: {}}\n');

      final result = await push(pushed);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('Test failed: one is one.'));
      expect(result.stdout, isNot(contains('Affected tests were not run')));
    });
  });
}

/// A real repository with one Dart package and a passing test, for the
/// acceptance scenarios of `tests/affected` (AC-24 to AC-27).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'fixture_package.dart';
import 'temp_repo.dart';

/// `tests/affected` on pre-push only.
const affectedConfig =
    'hooks:\n  pre-commit: []\n  pre-push: [tests/affected]\n';

/// A library with one function, and the test that expects it to return 1.
const libraryOne = 'int one() => 1;\n';

/// The same function, broken: the test of [libraryOne] now fails.
const libraryBroken = 'int one() => 2;\n';

/// A test of `lib/a.dart` that passes with [libraryOne] only.
const testOfOne =
    "import 'package:test/test.dart';\n"
    "import '../lib/a.dart';\n"
    '\n'
    'void main() {\n'
    "  test('one is one', () => expect(one(), 1));\n"
    '}\n';

/// A test that depends on nothing and always fails.
const alwaysFailing =
    "import 'package:test/test.dart';\n"
    '\n'
    'void main() {\n'
    "  test('never passes', () => expect(1, 2));\n"
    '}\n';

/// A repository on `main` with a committed package `app`: `lib/a.dart`,
/// `test/a_test.dart`, `stagelatch.yaml` and a `.gitignore`.
///
/// `dart pub get --offline` has been run, so `.dart_tool/package_config.json`
/// and `pubspec.lock` exist on disk. The lock is committed only with
/// [commitLock]; [gitignore] is the content of `.gitignore`. [files] are
/// written and committed too, and replace a default of the same path.
///
/// The caller disposes the repository.
Future<TempRepo> createAffectedRepo({
  Map<String, String> files = const {},
  String gitignore = '.dart_tool/\n',
  bool commitLock = false,
}) async {
  final repo = await TempRepo.create();
  final all = {
    'stagelatch.yaml': affectedConfig,
    '.gitignore': gitignore,
    'pubspec.yaml':
        'name: app\n'
        'publish_to: none\n'
        '\n'
        'environment:\n'
        '  sdk: ^3.0.0\n'
        '\n'
        'dev_dependencies:\n'
        '  test: ^1.33.0\n',
    'lib/a.dart': libraryOne,
    'test/a_test.dart': testOfOne,
    ...files,
  };
  for (final MapEntry(:key, :value) in all.entries) {
    await repo.write(key, value);
  }
  await pubGetOffline(repo.root);
  for (final path in [...all.keys, if (commitLock) 'pubspec.lock']) {
    await repo.stage(path);
  }
  await repo.commit('app');
  return repo;
}

/// Writes [content] to [path], commits it and returns the new commit.
Future<String> commitChange(
  TempRepo repo,
  String path,
  String content, {
  String? message,
}) async {
  await repo.write(path, content);
  await repo.stage(path);
  await repo.commit(message ?? 'change $path');
  return await sha(repo, 'HEAD');
}

/// The commit [rev] names.
Future<String> sha(TempRepo repo, String rev) async =>
    (await repo.git(['rev-parse', rev])).trim();

/// The standard input git gives the hook when [branch] is pushed from
/// [local] over [remote] (`'0' * 40` for a branch the remote lacks).
String pushOf(String branch, String local, String remote) =>
    'refs/heads/$branch $local refs/heads/$branch $remote\n';

/// Appends a comment to [path] on disk without staging it: an unstaged edit.
Future<void> editUnstaged(TempRepo repo, String path) async {
  final file = File(p.join(repo.root, path));
  await file.writeAsString('${await file.readAsString()}// edited\n');
}

/// The text of the dirty-skip warning for [count] divergent files.
String skipWarning(int count) =>
    'Affected tests were not run: $count file(s) they execute differ from '
    'the working tree (uncommitted changes, untracked files, or another '
    'checked-out commit).';

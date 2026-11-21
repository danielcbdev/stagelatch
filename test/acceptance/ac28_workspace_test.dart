@Tags(['git'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/affected_repo.dart';
import '../support/fixture_package.dart';
import '../support/temp_repo.dart';

/// AC-28: pub workspace — member analysis uses the root package config;
/// lockfile-out-of-sync reads the root lock; `tests/affected` selects and
/// runs another member's tests; `why` explains it.
void main() {
  late TempRepo repo;
  late String remote;

  tearDown(() async => await repo.dispose());

  Future<void> setUpWorkspace({
    Map<String, String> extra = const {},
    String config = affectedConfig,
  }) async {
    final fixture = await copyWorkspaceFixture();
    addTearDown(() => Directory(fixture).delete(recursive: true));
    repo = await TempRepo.create();
    await _copyTree(fixture, repo.root);
    await repo.write('stagelatch.yaml', config);
    await repo.write('.gitignore', '.dart_tool/\n');
    for (final MapEntry(:key, :value) in extra.entries) {
      await repo.write(key, value);
    }
    // The package config is not versioned; pub get on the work tree
    // supplies it for analyze and dart test.
    await pubGetOffline(repo.root);
    for (final entity in Directory(repo.root).listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.split(p.relative(entity.path, from: repo.root));
      if (relative.contains('.git') || relative.contains('.dart_tool')) {
        continue;
      }
      await repo.stage(p.joinAll(relative));
    }
    await repo.commit('workspace');
    remote = await sha(repo, 'HEAD');
  }

  test(
    'a member file is analyzed with the workspace root package config',
    () async {
      await setUpWorkspace(
        config:
            'hooks:\n  pre-commit: [analyze]\n'
            'analyze:\n  fail_on: [error, warning, info]\n',
      );
      await repo.write(
        'analysis_options.yaml',
        'linter:\n  rules:\n    - avoid_print\n',
      );
      await repo.write(
        'packages/a/lib/a.dart',
        "import 'package:b/b.dart';\n\n"
            'int twice() => value() * 2;\n\n'
            "void unused() { print('x'); }\n",
      );
      await repo.stage('analysis_options.yaml');
      await repo.stage('packages/a/lib/a.dart');

      final result = await repo.stagelatch(['run', 'pre-commit']);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('packages/a/lib/a.dart:'));
      expect(result.stdout, contains('analyze/avoid_print'));
    },
  );

  test('lockfile-out-of-sync reads the root lock for a member', () async {
    await setUpWorkspace(config: 'hooks:\n  pre-commit: [pubspec]\n');
    await repo.write(
      'packages/a/pubspec.yaml',
      'name: a\n'
          'publish_to: none\n'
          '\n'
          'environment:\n'
          '  sdk: ^3.13.0\n'
          '\n'
          'resolution: workspace\n'
          '\n'
          'dependencies:\n'
          '  b: any\n'
          '  http: ^1.2.0\n'
          '\n'
          'dev_dependencies:\n'
          '  test: ^1.33.0\n',
    );
    await repo.stage('packages/a/pubspec.yaml');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 1, reason: result.stdout + result.stderr);
    expect(result.stdout, contains('pubspec/lockfile-out-of-sync'));
    expect(result.stdout, contains('packages/a/pubspec.yaml'));
  });

  test('a change in one member selects and runs tests of another that '
      'imports it; why explains it', () async {
    await setUpWorkspace(
      extra: {
        'packages/a/lib/a.dart':
            "import 'package:b/b.dart';\n\n"
            'int twice() => value() * 2;\n',
        'packages/a/test/a_test.dart':
            "import 'package:test/test.dart';\n"
            "import 'package:a/a.dart';\n"
            '\n'
            'void main() {\n'
            "  test('twice', () => expect(twice(), 2));\n"
            '}\n',
      },
    );
    remote = await sha(repo, 'HEAD');
    final pushed = await commitChange(
      repo,
      'packages/b/lib/b.dart',
      'int value() => 2;\n',
    );

    final push = await repo.stagelatch([
      'run',
      'pre-push',
    ], stdin: pushOf('main', pushed, remote));

    expect(push.exitCode, 1, reason: push.stdout + push.stderr);
    expect(push.stdout, contains('Test failed'));
    expect(push.stdout, contains('packages/a/test/a_test.dart'));

    final why = await repo.stagelatch([
      'why',
      'packages/a/test/a_test.dart',
      '--base',
      remote,
    ]);
    expect(why.exitCode, 0, reason: why.stdout + why.stderr);
    expect(why.stdout, contains('packages/b/lib/b.dart'));
  });

  test(
    'an unstaged workspace root pubspec.yaml skips affected tests',
    () async {
      await setUpWorkspace(
        extra: {
          'packages/a/lib/a.dart':
              "import 'package:b/b.dart';\n\n"
              'int twice() => value() * 2;\n',
          'packages/a/test/a_test.dart':
              "import 'package:test/test.dart';\n"
              "import 'package:a/a.dart';\n"
              '\n'
              'void main() {\n'
              "  test('twice', () => expect(twice(), 2));\n"
              '}\n',
        },
      );
      remote = await sha(repo, 'HEAD');
      final pushed = await commitChange(
        repo,
        'packages/b/lib/b.dart',
        'int value() => 2;\n',
      );
      await editUnstaged(repo, 'pubspec.yaml');

      final result = await repo.stagelatch([
        'run',
        'pre-push',
      ], stdin: pushOf('main', pushed, remote));

      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
      expect(result.stdout, contains(skipWarning(1)));
      expect(result.stdout, isNot(contains('Test failed')));
    },
  );
}

Future<void> _copyTree(String from, String to) async {
  await for (final entity in Directory(from).list(recursive: true)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: from);
    final target = File(p.join(to, relative));
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}

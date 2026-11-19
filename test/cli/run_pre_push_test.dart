@Tags(['git'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  late TempRepo repo;
  late Directory remote;

  Future<String> head() async => (await repo.git(['rev-parse', 'HEAD'])).trim();

  Future<String> line() async {
    final sha = await head();
    return 'refs/heads/main $sha refs/heads/main ${'0' * sha.length}\n';
  }

  setUp(() async {
    repo = await TempRepo.create();
    remote = await Directory.systemTemp.createTemp('stagelatch_remote_');
    await repo.git(['init', '-q', '--bare', remote.path]);
    await repo.git(['remote', 'add', 'origin', remote.path]);
  });

  tearDown(() async {
    await repo.dispose();
    await remote.delete(recursive: true);
  });

  test(
    'the hook arguments <remote> <url> are accepted, with or without --',
    () async {
      final input = await line();

      final plain = await repo.stagelatch([
        'run',
        'pre-push',
        'origin',
        'https://example.invalid/r.git',
      ], stdin: input);
      final dashed = await repo.stagelatch([
        'run',
        'pre-push',
        '--',
        'origin',
        'u',
      ], stdin: input);

      expect(plain.exitCode, 0, reason: plain.stderr);
      expect(dashed.exitCode, 0, reason: dashed.stderr);
      expect(plain.stdout, startsWith('stagelatch pre-push main: '));
    },
  );

  test('one extra argument is the unknown-hook usage error', () async {
    final result = await repo.stagelatch(['run', 'pre-push', 'origin']);

    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains(
        'Unknown hook "pre-push origin". Expected pre-commit or pre-push.',
      ),
    );
  });

  test('pre-commit accepts no extra argument', () async {
    final result = await repo.stagelatch(['run', 'pre-commit', 'x', 'y']);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Unknown hook "pre-commit x y".'));
  });

  test(
    'a configured pre-push check judges the pushed commit and blocks',
    () async {
      await repo.write('stagelatch.yaml', 'hooks:\n  pre-push: [pubspec]\n');
      await repo.write('pubspec.yaml', badPubspec);
      await repo.stage('stagelatch.yaml');
      await repo.stage('pubspec.yaml');
      await repo.commit('bad');

      final result = await repo.stagelatch([
        'run',
        'pre-push',
        'origin',
        remote.path,
      ], stdin: await line());

      expect(result.exitCode, 1);
      expect(result.stdout, contains('pubspec/path-dependency'));
      expect(result.stdout, contains('Push blocked.'));
    },
  );

  test('without stdin, the current branch is pushed', () async {
    final result = await repo.stagelatch(['run', 'pre-push']);

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, startsWith('stagelatch pre-push main: '));
  });

  test('a malformed input line is a usage error', () async {
    final result = await repo.stagelatch([
      'run',
      'pre-push',
      'origin',
      'u',
    ], stdin: 'nonsense\n');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Malformed pre-push input: "nonsense".'));
  });

  test('a tag push has nothing to check', () async {
    final sha = await head();

    final result = await repo.stagelatch([
      'run',
      'pre-push',
      'origin',
      'u',
    ], stdin: 'refs/tags/v1 $sha refs/tags/v1 ${'0' * sha.length}\n');

    expect(result.exitCode, 0);
    expect(result.stdout, 'stagelatch: nothing to check.\n');
  });
}

import 'dart:io';

import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/shim.dart';
import '../support/temp_repo.dart';

/// AC-19: pre-push for an existing branch, a new branch, a branch deletion
/// and a tag push, and a real `git push` through the hook `init` installs.
void main() {
  late TempRepo repo;
  late Directory remote;

  Future<String> sha(String rev) async =>
      (await repo.git(['rev-parse', rev])).trim();

  Future<void> commitFile(String path, String content) async {
    await repo.write(path, content);
    await repo.stage(path);
    await repo.commit('change $path');
  }

  Future<CliResult> prePush(String stdin) =>
      repo.stagelatch(['run', 'pre-push', 'origin', remote.path], stdin: stdin);

  setUp(() async {
    repo = await TempRepo.create();
    remote = await Directory.systemTemp.createTemp('stagelatch_remote_');
    await repo.git(['init', '-q', '--bare', remote.path]);
    await repo.git(['remote', 'add', 'origin', remote.path]);
    await commitFile('stagelatch.yaml', 'hooks:\n  pre-push: [pubspec]\n');
    await repo.git(['push', '-q', 'origin', 'main']);
  });

  tearDown(() async {
    await repo.dispose();
    await remote.delete(recursive: true);
  });

  test(
    'existing branch: only the commits not on the remote are judged',
    () async {
      final remoteSha = await sha('HEAD');
      await commitFile('pubspec.yaml', badPubspec);

      final result = await prePush(
        'refs/heads/main ${await sha('HEAD')} refs/heads/main $remoteSha\n',
      );

      expect(result.exitCode, 1);
      expect(result.stdout, startsWith('stagelatch pre-push main: 1 file\n'));
      expect(result.stdout, contains('Push blocked.'));
    },
  );

  test(
    'new branch: a violation already on the remote is not judged again',
    () async {
      await commitFile('pubspec.yaml', badPubspec);
      await repo.git(['push', '-q', 'origin', 'main']);
      await repo.git(['switch', '-q', '-c', 'feature']);
      await commitFile('notes.txt', 'n\n');
      final head = await sha('HEAD');

      final result = await prePush(
        'refs/heads/feature $head refs/heads/feature ${'0' * head.length}\n',
      );

      expect(result.exitCode, 0, reason: result.stdout);
      expect(
        result.stdout,
        startsWith('stagelatch pre-push feature: 1 file\n'),
      );
    },
  );

  test('a branch deletion has nothing to check', () async {
    final head = await sha('HEAD');

    final result = await prePush(
      '(delete) ${'0' * head.length} refs/heads/old $head\n',
    );

    expect(result.exitCode, 0);
    expect(result.stdout, 'stagelatch: nothing to check.\n');
  });

  test('a tag push has nothing to check', () async {
    final head = await sha('HEAD');

    final result = await prePush(
      'refs/tags/v1 $head refs/tags/v1 ${'0' * head.length}\n',
    );

    expect(result.exitCode, 0);
    expect(result.stdout, 'stagelatch: nothing to check.\n');
  });

  test('a real git push runs the hook installed by init', () async {
    expect((await repo.stagelatch(['init', '--force'])).exitCode, 0);
    await repo.git(['checkout', '-q', '--', 'stagelatch.yaml']);
    final shim = await createShimDirectory();
    addTearDown(() => Directory(shim).delete(recursive: true));
    final env = {'PATH': pathWithShim(shim)};

    await commitFile('notes.txt', 'n\n');
    final clean = await runGit(repo, ['push', 'origin', 'main'], env: env);
    expect(clean.code, 0, reason: clean.stderr);

    await commitFile('pubspec.yaml', badPubspec);
    final blocked = await runGit(repo, ['push', 'origin', 'main'], env: env);
    expect(blocked.code, isNot(0), reason: blocked.stderr);
    expect(blocked.stdout + blocked.stderr, contains('Push blocked'));
  });
}

@Tags(['git'])
library;

import 'dart:convert';

import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

void main() {
  late TempRepo repo;
  late GitProcess git;

  setUp(() async {
    repo = await TempRepo.create();
    git = GitProcess(
      workingDirectory: repo.root,
      environment: repo.environment,
    );
  });

  tearDown(() => repo.dispose());

  group('GitProcess.run', () {
    test('runs in the given working directory', () async {
      final result = await git.run(['rev-parse', '--is-inside-work-tree']);

      expect(result.exitCode, 0);
      expect(result.text.trim(), 'true');
    });

    test('returns standard output split on NUL', () async {
      await repo.write('a b.txt', 'x');
      await repo.stage('a b.txt');

      final result = await git.run(['ls-files', '-z']);

      expect(result.nulSeparated, ['README.md', 'a b.txt']);
    });

    test('feeds standard input to git', () async {
      final result = await git.run([
        'hash-object',
        '--stdin',
      ], stdin: utf8.encode('hello\n'));

      // The well-known blob id of "hello\n".
      expect(result.text.trim(), 'ce013625030ba8dba906f756967f9e9ca394464a');
    });

    test('does not hang when git expects input and none is given', () async {
      final result = await git.run(['hash-object', '--stdin']);

      // The blob id of empty content.
      expect(result.text.trim(), 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391');
    });

    test('raises InternalException naming command and error output', () {
      expect(
        () => git.run(['rev-parse', '--verify', 'no-such-ref']),
        throwsA(
          isA<InternalException>()
              .having(
                (error) => error.message,
                'message',
                startsWith(
                  'git rev-parse --verify no-such-ref exited with 128: ',
                ),
              )
              .having((error) => error.where, 'where', 'git'),
        ),
      );
    });

    test('accepts an exit code the caller declares as expected', () async {
      final result = await git.run(
        ['rev-parse', '--verify', '--quiet', 'no-such-ref'],
        okExitCodes: {0, 1},
      );

      expect(result.exitCode, 1);
    });

    test('passes the environment through to git', () async {
      final custom = GitProcess(
        workingDirectory: repo.root,
        environment: {...repo.environment, 'GIT_AUTHOR_NAME': 'From Env'},
      );

      final result = await custom.run(['var', 'GIT_AUTHOR_IDENT']);

      expect(result.text, startsWith('From Env <test@example.com>'));
    });

    test('a missing executable is a usage error', () {
      final missing = GitProcess(
        workingDirectory: repo.root,
        environment: repo.environment,
        executable: 'stagelatch-no-such-git',
      );

      expect(
        () => missing.run(['version']),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            'Could not run git. Is it installed and on PATH?',
          ),
        ),
      );
    });
  });

  group('GitProcess.start', () {
    test('starts a long-lived process the caller drives', () async {
      final process = await git.start(['cat-file', '--batch-check']);

      process.stdin.writeln('HEAD');
      await process.stdin.flush();
      final firstLine = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      await process.stdin.close();

      expect(firstLine, matches(RegExp(r'^[0-9a-f]{40} commit \d+$')));
      expect(await process.exitCode, 0);
    });
  });
}

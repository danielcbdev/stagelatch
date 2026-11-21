@Tags(['git'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/infrastructure/git/git_cli_repository.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

void main() {
  late TempRepo repo;
  late GitCliRepository git;

  Future<String> sha(String rev) async =>
      (await repo.git(['rev-parse', rev])).trim();

  Future<void> commitFile(String path, String content) async {
    await repo.write(path, content);
    await repo.stage(path);
    await repo.commit('change $path');
  }

  GitCliRepository open(String directory) => GitCliRepository(
    git: GitProcess(workingDirectory: directory, environment: repo.environment),
  );

  setUp(() async {
    repo = await TempRepo.create();
    git = open(repo.root);
  });

  tearDown(() async {
    await git.close();
    await repo.dispose();
  });

  test('the base is the merge base of --base and HEAD', () async {
    await commitFile('base.txt', 'b\n');
    await repo.git(['switch', '-q', '-c', 'feature']);
    await commitFile('feature.txt', 'f\n');
    await repo.git(['switch', '-q', 'main']);
    await commitFile('main_only.txt', 'm\n');
    await repo.git(['switch', '-q', 'feature']);
    await repo.write('staged.txt', 's\n');
    await repo.stage('staged.txt');
    final forkPoint = await sha('feature~1');

    final run = await git.resolveAgainstIndex(baseRef: 'main');

    expect(run.snapshot, const IndexSnapshot());
    expect(run.base, CommitSnapshot(forkPoint));
    expect(run.label, 'index');
    expect([
      for (final change in run.changes.changes) change.path.value,
    ], contains('staged.txt'));
    expect([
      for (final change in run.changes.changes) change.path.value,
    ], isNot(contains('main_only.txt')));
  });

  test('the default base is the merge base with the upstream', () async {
    await commitFile('a.txt', 'a\n');
    final clones = await Directory.systemTemp.createTemp('stagelatch_up_');
    addTearDown(() => clones.delete(recursive: true));
    final bare = p.join(clones.path, 'bare.git');
    await repo.git(['clone', '-q', '--bare', repo.root, bare]);
    await repo.git(['remote', 'add', 'origin', bare]);
    await repo.git(['fetch', '-q', 'origin']);
    await repo.git(['branch', '--set-upstream-to=origin/main', 'main']);
    await commitFile('local.txt', 'l\n');
    await repo.write('staged.txt', 's\n');
    await repo.stage('staged.txt');
    final base = await sha('main@{upstream}');
    final mergeBase = (await repo.git([
      'merge-base',
      'main@{upstream}',
      'HEAD',
    ])).trim();

    final run = await git.resolveAgainstIndex();

    expect(run.base, CommitSnapshot(mergeBase));
    expect(base, isNotEmpty);
    expect([
      for (final change in run.changes.changes) change.path.value,
    ], containsAll(['local.txt', 'staged.txt']));
  });

  test('without an upstream the remote default branch is used', () async {
    await commitFile('a.txt', 'a\n');
    final clones = await Directory.systemTemp.createTemp('stagelatch_def_');
    addTearDown(() => clones.delete(recursive: true));
    final bare = p.join(clones.path, 'bare.git');
    await repo.git(['clone', '-q', '--bare', repo.root, bare]);
    await repo.git(['remote', 'add', 'origin', bare]);
    await repo.git(['fetch', '-q', 'origin']);
    await repo.git([
      'symbolic-ref',
      'refs/remotes/origin/HEAD',
      'refs/remotes/origin/main',
    ]);
    await repo.git(['switch', '-q', '-c', 'topic']);
    await commitFile('topic.txt', 't\n');
    await repo.write('staged.txt', 's\n');
    await repo.stage('staged.txt');
    final mergeBase = (await repo.git([
      'merge-base',
      'refs/remotes/origin/HEAD',
      'HEAD',
    ])).trim();

    final run = await git.resolveAgainstIndex();

    expect(run.base, CommitSnapshot(mergeBase));
    expect([
      for (final change in run.changes.changes) change.path.value,
    ], contains('staged.txt'));
  });

  test('no base at all is a usage error with the documented message', () async {
    await commitFile('a.txt', 'a\n');

    await expectLater(
      git.resolveAgainstIndex(),
      throwsA(
        isA<UsageException>().having(
          (e) => e.message,
          'message',
          'Cannot determine a base. Pass --base <ref>.',
        ),
      ),
    );
  });

  test('a missing merge base is the same usage error as ci', () async {
    await commitFile('a.txt', 'a\n');
    await repo.git(['switch', '-q', '-c', 'feature']);
    await commitFile('f.txt', 'f\n');
    final clones = await Directory.systemTemp.createTemp('stagelatch_shallow_');
    addTearDown(() => clones.delete(recursive: true));
    final clone = p.join(clones.path, 'clone');
    await repo.git([
      'clone',
      '-q',
      '--depth',
      '1',
      '--branch',
      'feature',
      Uri.directory(repo.root).toString(),
      clone,
    ]);
    final shallow = open(clone);
    addTearDown(shallow.close);

    await expectLater(
      shallow.resolveAgainstIndex(baseRef: 'origin/main'),
      throwsA(
        isA<UsageException>().having(
          (e) => e.message,
          'message',
          'Cannot find a merge base between origin/main and HEAD. If this is '
              'a shallow clone, fetch full history (actions/checkout: '
              'fetch-depth: 0).',
        ),
      ),
    );
  });

  test('staged changes count and unstaged ones do not', () async {
    await commitFile('tracked.txt', 't\n');
    await repo.write('staged.txt', 's\n');
    await repo.stage('staged.txt');
    await repo.write('unstaged.txt', 'u\n');
    await repo.write('tracked.txt', 'changed\n');

    final run = await git.resolveAgainstIndex(baseRef: 'HEAD');

    expect(
      [
        for (final change in run.changes.changes)
          (change.path.value, change.kind),
      ],
      [('staged.txt', ChangeKind.added)],
    );
  });
}

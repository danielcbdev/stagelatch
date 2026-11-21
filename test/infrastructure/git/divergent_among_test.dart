@Tags(['git'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/git/git_cli_repository.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

Set<RepoPath> paths(Iterable<String> values) => {
  for (final value in values) RepoPath(value),
};

void main() {
  late TempRepo repo;
  late GitCliRepository git;

  GitCliRepository open(String directory) => GitCliRepository(
    git: GitProcess(workingDirectory: directory, environment: repo.environment),
  );

  Future<void> commitFile(String path, String content, String message) async {
    await repo.write(path, content);
    await repo.stage(path);
    await repo.commit(message);
  }

  Future<CommitSnapshot> head() async =>
      CommitSnapshot((await repo.git(['rev-parse', 'HEAD'])).trim());

  setUp(() async {
    repo = await TempRepo.create();
    git = open(repo.root);
  });

  tearDown(() async {
    await git.close();
    await repo.dispose();
  });

  test('a tracked file that differs from the index is divergent', () async {
    await commitFile('lib/a.dart', 'a\n', 'a');
    await repo.write('lib/a.dart', 'edited\n');

    expect(
      await git.divergentAmong(
        const IndexSnapshot(),
        paths(['lib/a.dart', 'README.md']),
      ),
      paths(['lib/a.dart']),
    );
  });

  test('a file equal to the snapshot is not divergent', () async {
    await commitFile('lib/a.dart', 'a\n', 'a');

    expect(
      await git.divergentAmong(const IndexSnapshot(), paths(['lib/a.dart'])),
      isEmpty,
    );
  });

  test('a divergent file outside the candidates is not reported', () async {
    await commitFile('lib/a.dart', 'a\n', 'a');
    await repo.write('lib/a.dart', 'edited\n');

    expect(
      await git.divergentAmong(const IndexSnapshot(), paths(['README.md'])),
      isEmpty,
    );
  });

  test('a deleted tracked file is divergent', () async {
    await commitFile('lib/a.dart', 'a\n', 'a');
    await repo.delete('lib/a.dart');

    expect(
      await git.divergentAmong(const IndexSnapshot(), paths(['lib/a.dart'])),
      paths(['lib/a.dart']),
    );
  });

  test('an untracked file absent from the snapshot is divergent when git '
      'would track it', () async {
    await repo.write('lib/new.dart', 'x\n');

    expect(
      await git.divergentAmong(
        const IndexSnapshot(),
        paths(['lib/new.dart', 'lib/missing.dart']),
      ),
      paths(['lib/new.dart']),
    );
  });

  test('an untracked ignored file is not divergent', () async {
    await commitFile('.gitignore', 'lib/*.g.dart\n', 'ignore');
    await repo.write('lib/a.g.dart', 'x\n');
    await repo.write('lib/b.dart', 'x\n');

    expect(
      await git.divergentAmong(
        const IndexSnapshot(),
        paths(['lib/a.g.dart', 'lib/b.dart']),
      ),
      paths(['lib/b.dart']),
    );
  });

  test('a directory at the path is not a regular file', () async {
    await Directory(p.join(repo.root, 'lib', 'dir.dart'))
        .create(recursive: true);

    expect(
      await git.divergentAmong(const IndexSnapshot(), paths(['lib/dir.dart'])),
      isEmpty,
    );
  });

  test('a symlink at the path is not a regular file', () async {
    await repo.write('lib/target.dart', 'x\n');
    await Link(p.join(repo.root, 'lib', 'link.dart'))
        .create(p.join(repo.root, 'lib', 'target.dart'));

    expect(
      await git.divergentAmong(const IndexSnapshot(), paths(['lib/link.dart'])),
      isEmpty,
    );
  }, testOn: '!windows');

  test('a commit that is not checked out: the files of the closure that '
      'differ are divergent', () async {
    await commitFile('lib/a.dart', 'a\n', 'a');
    await commitFile('lib/b.dart', 'b\n', 'b');
    final main = await head();
    await repo.git(['switch', '--quiet', '-c', 'other', 'HEAD~1']);
    await commitFile('lib/a.dart', 'a2\n', 'a again');
    final other = await head();
    await repo.git(['switch', '--quiet', 'main']);

    expect(
      await git.divergentAmong(
        other,
        paths(['lib/a.dart', 'lib/b.dart', 'README.md']),
      ),
      paths(['lib/a.dart', 'lib/b.dart']),
    );
    expect(
      await git.divergentAmong(main, paths(['lib/a.dart', 'lib/b.dart'])),
      isEmpty,
    );
  });

  test('a file in the pushed commit that is untracked in the working tree is '
      'divergent', () async {
    await commitFile('lib/a.dart', 'a\n', 'a');
    final pushed = await head();
    await repo.git(['rm', '--cached', '--quiet', 'lib/a.dart']);

    expect(await git.divergentAmong(pushed, paths(['lib/a.dart'])), {
      RepoPath('lib/a.dart'),
    });
  });

  test('a file the pushed commit lacks and the working tree has, ignored, '
      'is not divergent', () async {
    await commitFile('.gitignore', '*.g.dart\n', 'ignore');
    final pushed = await head();
    await repo.write('lib/a.g.dart', 'x\n');

    expect(await git.divergentAmong(pushed, paths(['lib/a.g.dart'])), isEmpty);
  });

  test('paths with spaces and non-ASCII characters are checked', () async {
    await repo.write('lib/a b.dart', 'x\n');
    await repo.write('lib/á.dart', 'x\n');
    await repo.write('lib/ignored é.dart', 'x\n');
    await commitFile('.gitignore', 'ignored*\n', 'ignore');

    expect(
      await git.divergentAmong(
        const IndexSnapshot(),
        paths(['lib/a b.dart', 'lib/á.dart', 'lib/ignored é.dart']),
      ),
      paths(['lib/a b.dart', 'lib/á.dart']),
    );
  });

  test(
    'from a subdirectory the paths are still those of the repository',
    () async {
      await repo.write('lib/new.dart', 'x\n');
      await repo.write('lib/ignored.g.dart', 'x\n');
      await commitFile('.gitignore', '*.g.dart\n', 'ignore');
      final inLib = open(p.join(repo.root, 'lib'));
      addTearDown(inLib.close);

      expect(
        await inLib.divergentAmong(
          const IndexSnapshot(),
          paths(['lib/new.dart', 'lib/ignored.g.dart']),
        ),
        paths(['lib/new.dart']),
      );
    },
  );

  test('two thousand candidates are answered with one check-ignore', () async {
    await commitFile('.gitignore', '*.g.dart\n', 'ignore');
    final candidates = <String>[];
    for (var index = 0; index < 2000; index++) {
      final name = index.isEven ? 'lib/f$index.dart' : 'lib/f$index.g.dart';
      candidates.add(name);
      await repo.write(name, 'x\n');
    }
    // A git that logs its subcommand before running the real one.
    final log = p.join(repo.root, '..', 'git.log');
    final wrapper = p.join(repo.root, '..', 'git-wrapper');
    await File(wrapper)
        .writeAsString('#!/bin/sh\necho "\$@" >> "$log"\nexec git "\$@"\n');
    await Process.run('chmod', ['755', wrapper]);
    final counted = GitCliRepository(
      git: GitProcess(
        workingDirectory: repo.root,
        environment: repo.environment,
        executable: wrapper,
      ),
    );
    addTearDown(counted.close);

    final divergent = await counted.divergentAmong(
      const IndexSnapshot(),
      paths(candidates),
    );

    expect(
      divergent,
      paths([for (var i = 0; i < 2000; i += 2) 'lib/f$i.dart']),
    );
    final calls = await File(log).readAsLines();
    expect(
      calls.where((line) => line.startsWith('check-ignore')),
      hasLength(1),
    );
  }, testOn: '!windows');
}

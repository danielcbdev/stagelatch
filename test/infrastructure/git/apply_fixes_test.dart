@Tags(['git'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/fix.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/infrastructure/git/git_cli_repository.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

const _rule = RuleId('format', 'unformatted');

Fix _fix(String path, String content) =>
    Fix(rule: _rule, path: RepoPath(path), content: content);

void main() {
  late TempRepo repo;
  late GitCliRepository git;

  GitCliRepository open({Map<String, String> more = const {}}) =>
      GitCliRepository(
        git: GitProcess(
          workingDirectory: repo.root,
          environment: {...repo.environment, ...more},
        ),
      );

  Future<void> commitFile(String path, String content) async {
    await repo.write(path, content);
    await repo.stage(path);
    await repo.commit('add $path');
  }

  setUp(() async {
    repo = await TempRepo.create();
    git = open();
  });

  tearDown(() async {
    await git.close();
    await repo.dispose();
  });

  test('a clean file is fixed in the index and in the working tree', () async {
    await commitFile('a.dart', 'before\n');

    final applied = await git.applyFixes([_fix('a.dart', 'fixed\n')]);

    expect(await repo.git(['show', ':a.dart']), 'fixed\n');
    expect(await repo.read('a.dart'), 'fixed\n');
    expect(applied, [
      AppliedFix(rule: _rule, path: RepoPath('a.dart'), worktreeUpdated: true),
    ]);
  });

  test('a partially staged file is fixed in the index only', () async {
    await commitFile('a.dart', 'old\n');
    await repo.write('a.dart', 'staged\nunstaged\n');
    await repo.stageContent('a.dart', 'staged\n');

    final applied = await git.applyFixes([_fix('a.dart', 'fixed\n')]);

    expect(await repo.git(['show', ':a.dart']), 'fixed\n');
    expect(await repo.read('a.dart'), 'staged\nunstaged\n');
    expect(applied.single.worktreeUpdated, isFalse);
  });

  test('the executable mode is preserved', () async {
    await commitFile('run.dart', 'before\n');
    await repo.git(['update-index', '--chmod=+x', 'run.dart']);

    await git.applyFixes([_fix('run.dart', 'fixed\n')]);

    expect(
      await repo.git(['ls-files', '-s', 'run.dart']),
      startsWith('100755 '),
    );
  });

  test('with core.autocrlf the index stays LF and the working tree gets '
      'CRLF', () async {
    await commitFile('a.dart', 'before\n');
    await repo.git(['config', 'core.autocrlf', 'true']);

    await git.applyFixes([_fix('a.dart', 'a\nb\n')]);

    expect(await repo.git(['show', ':a.dart']), 'a\nb\n');
    expect(File(p.join(repo.root, 'a.dart')).readAsStringSync(), 'a\r\nb\r\n');
  });

  test('paths with spaces and non-ASCII characters work', () async {
    await commitFile('dir with space/café.dart', 'before\n');

    final applied = await git.applyFixes([
      _fix('dir with space/café.dart', 'fixed\n'),
    ]);

    expect(await repo.git(['show', ':dir with space/café.dart']), 'fixed\n');
    expect(await repo.read('dir with space/café.dart'), 'fixed\n');
    expect(applied.single.worktreeUpdated, isTrue);
  });

  test(
    'a held index.lock raises InternalException and changes nothing',
    () async {
      await commitFile('a.dart', 'before\n');
      final lock = File(p.join(repo.root, '.git', 'index.lock'))
        ..writeAsStringSync('');
      addTearDown(lock.delete);

      await expectLater(
        git.applyFixes([_fix('a.dart', 'fixed\n')]),
        throwsA(
          isA<InternalException>().having(
            (e) => e.message,
            'message',
            contains('index.lock'),
          ),
        ),
      );
      expect(await repo.git(['show', ':a.dart']), 'before\n');
      expect(await repo.read('a.dart'), 'before\n');
    },
  );

  test('several fixes are applied by a single update-index call', () async {
    await commitFile('a.dart', 'a\n');
    await commitFile('b.dart', 'b\n');
    final traceDir = await Directory.systemTemp.createTemp('git_trace_');
    addTearDown(() => traceDir.delete(recursive: true));
    final trace = p.join(traceDir.path, 'trace.log');
    final traced = open(more: {'GIT_TRACE': trace});
    addTearDown(traced.close);

    await traced.applyFixes([_fix('a.dart', 'A\n'), _fix('b.dart', 'B\n')]);

    final calls = File(trace)
        .readAsLinesSync()
        .where((line) => line.contains('update-index'))
        .length;
    expect(calls, 1);
    expect(await repo.git(['show', ':b.dart']), 'B\n');
  });

  test('the index view is refreshed after fixes', () async {
    await commitFile('a.dart', 'before\n');
    final before = await git
        .files(const IndexSnapshot())
        .readText(RepoPath('a.dart'));

    await git.applyFixes([_fix('a.dart', 'fixed\n')]);

    expect(before, 'before\n');
    expect(
      await git.files(const IndexSnapshot()).readText(RepoPath('a.dart')),
      'fixed\n',
    );
  });

  test('no fixes is a no-op', () async {
    expect(await git.applyFixes(const []), isEmpty);
  });
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/shim.dart';
import '../support/temp_repo.dart';

void main() {
  test('install in a linked worktree writes the common hooks', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    final worktree = p.join(p.dirname(repo.root), 'linked');
    await repo.git(['worktree', 'add', '--quiet', '-b', 'side', worktree]);

    final installed = await repo.stagelatch(['-C', worktree, 'install']);
    final hooks = (await repo.git(['rev-parse', '--git-path', 'hooks'])).trim();
    final hooksDir = p.isAbsolute(hooks) ? hooks : p.join(repo.root, hooks);

    expect(installed.exitCode, 0);
    expect(File(p.join(hooksDir, 'pre-commit')).existsSync(), isTrue);

    final shim = await createShimDirectory();
    addTearDown(() => Directory(shim).delete(recursive: true));
    await File(p.join(worktree, 'pubspec.yaml')).writeAsString(badPubspec);
    final staged = await runGit(repo, [
      'add',
      '--',
      'pubspec.yaml',
    ], workingDirectory: worktree);
    expect(staged.code, 0, reason: staged.stderr);

    final committed = await runGit(
      repo,
      ['commit', '-m', 'should be blocked'],
      workingDirectory: worktree,
      env: {'PATH': pathWithShim(shim)},
    );
    final log = await runGit(repo, [
      'log',
      '--oneline',
    ], workingDirectory: worktree);

    expect(committed.code, isNot(0), reason: committed.stderr);
    expect(log.stdout, isNot(contains('should be blocked')));
  });
}

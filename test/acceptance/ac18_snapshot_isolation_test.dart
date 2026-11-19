import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

/// AC-18: the verdict comes from the snapshot alone. An unstaged edit in a
/// dependency, an untracked imported file and a file deleted only in the
/// index do not change it (ADR-0001).
void main() {
  late TempRepo repo;

  const config = 'hooks:\n  pre-commit: [analyze]\n';
  const user = "import 'dep.dart';\n\nint uses = dep;\n";

  setUp(() async {
    repo = await TempRepo.create();
    await addDartPackage(repo);
    await repo.write('stagelatch.yaml', config);
    await repo.stage('stagelatch.yaml');
    await repo.commit('config');
  });

  tearDown(() => repo.dispose());

  Future<CliResult> commit() => repo.stagelatch(['run', 'pre-commit']);

  test(
    'an imported file broken only in the working tree does not block',
    () async {
      await repo.write('lib/dep.dart', 'int dep = 1;\n');
      await repo.stage('lib/dep.dart');
      await repo.write('lib/dep.dart', 'int dep = "broken";\n');
      await repo.write('lib/user.dart', user);
      await repo.stage('lib/user.dart');

      final result = await commit();

      expect(result.exitCode, 0, reason: result.stdout);
    },
  );

  test('a file broken in the index but fixed on disk blocks', () async {
    await repo.write('lib/dep.dart', 'int dep = 1;\n');
    await repo.stageContent('lib/dep.dart', 'int dep = "broken";\n');

    final result = await commit();

    expect(result.exitCode, 1, reason: result.stdout);
    expect(result.stdout, contains('analyze/invalid_assignment'));
  });

  test('an untracked imported file is not part of the commit', () async {
    await repo.write('lib/dep.dart', 'int dep = 1;\n');
    await repo.write('lib/user.dart', user);
    await repo.stage('lib/user.dart');

    final result = await commit();

    expect(result.exitCode, 1, reason: result.stdout);
    expect(result.stdout, contains('analyze/uri_does_not_exist'));
  });

  test('a file removed from the index but kept on disk is gone for the '
      'commit', () async {
    await repo.write('lib/dep.dart', 'int dep = 1;\n');
    await repo.write('lib/user.dart', user);
    await repo.stage('lib/dep.dart');
    await repo.stage('lib/user.dart');
    await repo.commit('both');
    await repo.git(['rm', '-q', '--cached', 'lib/dep.dart']);
    await repo.write('lib/user.dart', '$user// touched\n');
    await repo.stage('lib/user.dart');

    final result = await commit();

    expect(result.exitCode, 1, reason: result.stdout);
    expect(result.stdout, contains('analyze/uri_does_not_exist'));
  });
}

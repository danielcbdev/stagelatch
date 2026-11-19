import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

/// AC-17: format autofix of a clean file and of a partially staged file,
/// the executable bit kept, and `format.fix: false` blocking instead.
void main() {
  late TempRepo repo;

  const unformatted = 'void main( ) {\n}\n';
  const formatted = 'void main() {}\n';

  setUp(() async {
    repo = await TempRepo.create();
    await addDartPackage(repo);
  });

  tearDown(() => repo.dispose());

  test('an unformatted staged file is fixed in the index and the working '
      'tree, and the commit is allowed', () async {
    await repo.write('lib/a.dart', unformatted);
    await repo.stage('lib/a.dart');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    expect(result.stdout, contains('lib/a.dart  fixed  format/unformatted'));
    expect(await repo.git(['show', ':lib/a.dart']), formatted);
    expect(await repo.read('lib/a.dart'), formatted);
  });

  test('with unstaged edits only the index is fixed', () async {
    await repo.write('lib/a.dart', '$unformatted// unstaged\n');
    await repo.stageContent('lib/a.dart', unformatted);

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    expect(await repo.git(['show', ':lib/a.dart']), formatted);
    expect(await repo.read('lib/a.dart'), '$unformatted// unstaged\n');
    expect(
      result.stdout,
      contains(
        'Fixed in the index only: the working tree copy has unstaged '
        'changes.',
      ),
    );
  });

  test('the executable bit is kept', () async {
    await repo.write('bin/run.dart', unformatted);
    await repo.stage('bin/run.dart');
    await repo.git(['update-index', '--chmod=+x', 'bin/run.dart']);

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    expect(
      await repo.git(['ls-files', '-s', 'bin/run.dart']),
      startsWith('100755 '),
    );
    expect(await repo.git(['show', ':bin/run.dart']), formatted);
  });

  test('format.fix: false blocks instead of fixing', () async {
    await repo.write('stagelatch.yaml', 'format:\n  fix: false\n');
    await repo.stage('stagelatch.yaml');
    await repo.write('lib/a.dart', unformatted);
    await repo.stage('lib/a.dart');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 1);
    expect(
      result.stdout,
      contains('lib/a.dart:1:11  error  format/unformatted'),
    );
    expect(await repo.git(['show', ':lib/a.dart']), unformatted);
  });
}

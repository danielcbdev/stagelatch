import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

/// AC-21: in a repository with two packages, each file is analyzed with
/// its own package's analysis_options.yaml.
void main() {
  test('each file gets its own package lints', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await addDartPackage(
      repo,
      analysisOptions: 'linter:\n  rules:\n    - avoid_print\n',
    );
    await addDartPackage(repo, dir: 'packages/ui', name: 'ui');
    await repo.write(
      'stagelatch.yaml',
      'hooks:\n  pre-commit: [analyze]\n'
          'analyze:\n  fail_on: [error, warning, info]\n',
    );
    await repo.stage('stagelatch.yaml');
    const printing = "void main() {\n  print('x');\n}\n";
    await repo.write('lib/a.dart', printing);
    await repo.write('packages/ui/lib/b.dart', printing);
    await repo.stage('lib/a.dart');
    await repo.stage('packages/ui/lib/b.dart');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 1, reason: result.stdout);
    expect(
      result.stdout,
      contains('lib/a.dart:2:3  error  analyze/avoid_print'),
    );
    expect(result.stdout, isNot(contains('packages/ui/lib/b.dart:')));
  });
}

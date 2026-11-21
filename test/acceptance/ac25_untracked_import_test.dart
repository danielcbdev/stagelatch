@Tags(['git'])
library;

import 'package:test/test.dart';

import '../support/affected_repo.dart';
import '../support/temp_repo.dart';

/// A test that imports [target] and fails whenever it can load it.
String _testImporting(String target) =>
    "import 'package:test/test.dart';\n"
    "import '$target';\n"
    '\n'
    'void main() {\n'
    "  test('generated is used', () => expect(generated(), 'never'));\n"
    '}\n';

const _generated = "String generated() => 'always';\n";

/// AC-25: an affected test that imports an untracked file that git would
/// track is not run; the same import of a gitignored file (generated code)
/// is (ADR-0018, rule 2).
void main() {
  late TempRepo repo;

  tearDown(() async => await repo.dispose());

  test('an untracked, non-ignored import target skips the run with the '
      'warning at the import', () async {
    repo = await createAffectedRepo();
    final remote = await sha(repo, 'HEAD');
    // The commit forgot to add lib/generated.dart: it is only on disk.
    await repo.write('lib/generated.dart', _generated);
    final pushed = await commitChange(
      repo,
      'test/a_test.dart',
      _testImporting('../lib/generated.dart'),
    );

    final result = await repo.stagelatch([
      'run',
      'pre-push',
    ], stdin: pushOf('main', pushed, remote));

    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    expect(result.stdout, contains(skipWarning(1)));
    expect(result.stdout, contains('test/a_test.dart:2:'));
    expect(result.stdout, isNot(contains('Test failed')));
  });

  test('a gitignored import target does not skip: the tests run', () async {
    repo = await createAffectedRepo(gitignore: '.dart_tool/\n*.g.dart\n');
    final remote = await sha(repo, 'HEAD');
    await repo.write('lib/generated.g.dart', _generated);
    final pushed = await commitChange(
      repo,
      'test/a_test.dart',
      _testImporting('../lib/generated.g.dart'),
    );

    final result = await repo.stagelatch([
      'run',
      'pre-push',
    ], stdin: pushOf('main', pushed, remote));

    expect(result.exitCode, 1, reason: result.stdout + result.stderr);
    expect(result.stdout, contains('Test failed: generated is used.'));
    expect(result.stdout, isNot(contains('Affected tests were not run')));
  });

  test('the target is found through a library the test does not name '
      'directly', () async {
    repo = await createAffectedRepo();
    final remote = await sha(repo, 'HEAD');
    await repo.write('lib/generated.dart', _generated);
    await repo.write('lib/b.dart', "export 'generated.dart';\n");
    await repo.stage('lib/b.dart');
    await repo.write('test/a_test.dart', _testImporting('../lib/b.dart'));
    await repo.stage('test/a_test.dart');
    await repo.commit('test through b');
    final pushed = await sha(repo, 'HEAD');

    final result = await repo.stagelatch([
      'run',
      'pre-push',
    ], stdin: pushOf('main', pushed, remote));

    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    expect(result.stdout, contains(skipWarning(1)));
    expect(result.stdout, contains('lib/b.dart:1:'));
  });
}

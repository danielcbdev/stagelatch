@Tags(['git'])
library;

import 'package:test/test.dart';

import '../support/temp_repo.dart';

void main() {
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
    await repo.write('pubspec.yaml', 'name: app\n');
    await repo.write('lib/a.dart', 'class A {}\n');
    await repo.write(
      'test/a_test.dart',
      "import 'package:app/a.dart';\nvoid main() {}\n",
    );
    await repo.stage('pubspec.yaml');
    await repo.stage('lib/a.dart');
    await repo.stage('test/a_test.dart');
    await repo.commit('app');
  });

  tearDown(() => repo.dispose());

  test(
    'prints the rendering and exits 0 whether the test is affected or not',
    () async {
      await repo.write('lib/a.dart', 'class A { void m() {} }\n');
      await repo.stage('lib/a.dart');

      final affected = await repo.stagelatch([
        'why',
        'test/a_test.dart',
        '--base',
        'HEAD',
      ]);

      expect(affected.exitCode, 0);
      expect(
        affected.stdout,
        startsWith('test/a_test.dart is affected by 1 changed file:\n'),
      );
      expect(affected.stdout, contains('lib/a.dart (changed)\n'));

      await repo.git(['checkout', '--', 'lib/a.dart']);
      await repo.git(['reset', '-q', 'HEAD', '--', 'lib/a.dart']);
      await repo.write('notes.txt', 'n\n');
      await repo.stage('notes.txt');

      final none = await repo.stagelatch([
        'why',
        'test/a_test.dart',
        '--base',
        'HEAD',
      ]);

      expect(none.exitCode, 0);
      expect(
        none.stdout,
        'test/a_test.dart is not affected by the current changes.\n',
      );
    },
  );

  test(
    'a path that is not a test file exits 64 with the message on stderr',
    () async {
      final result = await repo.stagelatch([
        'why',
        'lib/a.dart',
        '--base',
        'HEAD',
      ]);

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains('lib/a.dart is not a test file of any package.'),
      );
    },
  );
}

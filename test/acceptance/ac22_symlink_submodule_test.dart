import 'dart:io';

import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

/// AC-22: symlinks and submodule entries in the changeset are skipped by
/// content checks: no crash, no content finding.
void main() {
  test('a symlinked Dart file and a submodule entry are skipped', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await addDartPackage(repo);
    await repo.write(
      'stagelatch.yaml',
      'hooks:\n  pre-commit: [format, analyze, pubspec, sensitive-files]\n',
    );
    await repo.stage('stagelatch.yaml');
    await repo.write('lib/a.dart', 'void main() {}\n');
    await repo.stage('lib/a.dart');
    await Link('${repo.root}/lib/link.dart').create('a.dart');
    await repo.stage('lib/link.dart');
    final head = (await repo.git(['rev-parse', 'HEAD'])).trim();
    await repo.git([
      'update-index',
      '--add',
      '--cacheinfo',
      '160000,$head,vendor/sub',
    ]);

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    expect(result.stdout, contains('0 errors, 0 warnings. Commit allowed.'));
  }, testOn: '!windows');
}

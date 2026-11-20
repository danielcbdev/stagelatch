import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/temp_repo.dart';

/// AC-20: `ci` in a shallow clone without the base branch fails with the
/// fetch-depth message instead of analyzing a wrong diff.
void main() {
  test('ci in a shallow clone exits 64 with the fetch-depth message', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.write('a.txt', 'a\n');
    await repo.stage('a.txt');
    await repo.commit('a');
    await repo.git(['switch', '-q', '-c', 'feature']);
    await repo.write('f.txt', 'f\n');
    await repo.stage('f.txt');
    await repo.commit('f');
    final clones = await Directory.systemTemp.createTemp('stagelatch_clone_');
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

    final result = await repo.stagelatch([
      '-C',
      clone,
      'ci',
      '--base',
      'origin/main',
    ]);

    expect(result.exitCode, 64);
    expect(result.stdout, isEmpty);
    expect(
      result.stderr,
      'Cannot find a merge base between origin/main and HEAD. If this is a '
      'shallow clone, fetch full history (actions/checkout: '
      'fetch-depth: 0).\n',
    );
  });
}

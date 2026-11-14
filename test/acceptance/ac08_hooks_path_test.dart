import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/temp_repo.dart';

void main() {
  test('an unmanaged hook is refused, and --force keeps a backup', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.git(['config', 'core.hooksPath', '.husky']);
    await repo.write('.husky/pre-commit', '#!/bin/sh\nhusky\n');

    final refused = await repo.stagelatch(['install']);

    expect(refused.exitCode, 64);
    expect(await repo.read('.husky/pre-commit'), '#!/bin/sh\nhusky\n');
    expect(refused.stderr, contains('does not manage already exists'));

    final forced = await repo.stagelatch(['install', '--force']);
    final backup = File(
      p.join(repo.root, '.husky', 'pre-commit.stagelatch-backup'),
    );

    expect(forced.exitCode, 0);
    expect(await backup.readAsString(), '#!/bin/sh\nhusky\n');
    expect(
      await repo.read('.husky/pre-commit'),
      contains('# stagelatch:managed'),
    );
  });
}

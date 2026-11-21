@Tags(['git'])
library;

import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

/// Only `pubspec` runs, so the scenarios need no Dart SDK.
const _config = 'hooks:\n  pre-commit: [pubspec]\n  pre-push: []\n';
const _baselinePath = '.stagelatch/baseline.json';

void main() {
  late TempRepo repo;

  /// A legacy repository: one violation, committed, then accepted by a
  /// baseline that is committed too.
  Future<void> adopt() async {
    await repo.write('stagelatch.yaml', _config);
    await repo.stage('stagelatch.yaml');
    await repo.stageContent('pubspec.yaml', badPubspec);
    await repo.commit('legacy');
    final created = await repo.stagelatch(['baseline', 'create']);
    expect(created.exitCode, 0, reason: created.stderr);
    expect(
      created.stdout,
      'Wrote 1 entry to $_baselinePath. Stage it to take effect.\n',
    );
    await repo.stage(_baselinePath);
    await repo.commit('adopt stagelatch');
  }

  setUp(() async {
    repo = await TempRepo.create();
    await adopt();
  });

  tearDown(() => repo.dispose());

  test('a legacy violation that is baselined and staged passes', () async {
    await repo.stageContent('pubspec.yaml', '$badPubspec# touched\n');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 0, reason: result.stdout);
    expect(result.stdout, contains('Commit allowed.'));
    expect(result.stdout, contains('(0 suppressed, 1 baselined)'));
  });

  test('a new violation is blocked and only it is reported', () async {
    await repo.stageContent('other/pubspec.yaml', badPubspec);
    await repo.stageContent('pubspec.yaml', '$badPubspec# touched\n');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 1, reason: result.stdout);
    expect(result.stdout, contains('other/pubspec.yaml:4:11'));
    expect(result.stdout, isNot(contains('\npubspec.yaml:')));
    expect(result.stdout, contains('1 error, 0 warnings. Commit blocked.'));
    expect(result.stdout, contains('1 baselined'));
  });

  test('lines inserted above the violation keep it baselined', () async {
    await repo.stageContent(
      'pubspec.yaml',
      'name: app\n# one\n# two\n# three\ndependencies:\n'
          '  design_system:\n    path: ../x\n',
    );

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 0, reason: result.stdout);
    expect(result.stdout, contains('1 baselined'));
  });

  test('renaming the file brings the violation back, and prune drops the '
      'stale entry', () async {
    await repo.stageContent('app/pubspec.yaml', badPubspec);
    await repo.git(['rm', '--quiet', '-f', 'pubspec.yaml']);

    final blocked = await repo.stagelatch(['run', 'pre-commit']);
    expect(blocked.exitCode, 1, reason: blocked.stdout);
    expect(blocked.stdout, contains('app/pubspec.yaml:4:11'));

    final pruned = await repo.stagelatch(['baseline', 'prune']);
    expect(pruned.exitCode, 0, reason: pruned.stderr);
    expect(pruned.stdout, 'Removed 1 stale entry; 0 remain.\n');
  });

  test('create refuses to overwrite and prune never adds', () async {
    final refused = await repo.stagelatch(['baseline', 'create']);
    expect(refused.exitCode, 64);
    expect(
      refused.stderr,
      contains(
        '$_baselinePath already exists. Use --force to overwrite, '
        'or run: stagelatch baseline prune',
      ),
    );

    await repo.stageContent('other/pubspec.yaml', badPubspec);
    final pruned = await repo.stagelatch(['baseline', 'prune']);
    expect(pruned.exitCode, 0, reason: pruned.stderr);
    expect(pruned.stdout, 'Removed 0 stale entries; 1 remain.\n');
  });

  test('without a baseline file, prune says so', () async {
    await repo.git(['rm', '--quiet', '-f', _baselinePath]);

    final result = await repo.stagelatch(['baseline', 'prune']);

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, 'No baseline at $_baselinePath.\n');
  });
}

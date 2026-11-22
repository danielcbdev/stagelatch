@Tags(['git'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/infrastructure/custom/spawned_check_process.dart';
import 'package:test/test.dart';

import '../support/custom_checks.dart';
import '../support/temp_repo.dart';

/// AC-31: a custom check that never answers is killed when its timeout
/// expires. The run ends with exit 70 naming the check, well before the
/// child would have finished, and the child process is gone afterwards.
void main() {
  late TempRepo repo;
  late Directory scratch;

  setUp(() async {
    repo = await TempRepo.create();
    scratch = await Directory.systemTemp.createTemp('stagelatch-ac31-');
  });

  tearDown(() async {
    await SpawnedCheckProcess.killAllActive();
    await repo.dispose();
    await scratch.delete(recursive: true);
  });

  test('timeout kills the child and exits 70', () async {
    final pidFile = p.join(scratch.path, 'child.pid');
    await addFixtureCheck(repo, 'hanging_with_pid');
    await commitCustomCheckSetup(
      repo,
      customCheckConfig(
        run: ['dart', 'tool/check.dart', pidFile],
        timeout: '3s',
      ),
    );
    await repo.stageContent('lib/a.dart', 'void a() {}\n// changed\n');

    final clock = Stopwatch()..start();
    final result = await repo.stagelatch(['run', 'pre-commit']);
    clock.stop();

    expect(result.exitCode, 70, reason: result.stdout + result.stderr);
    expect(
      result.stderr,
      contains('custom check "probe": timed out after 3s.'),
    );
    expect(clock.elapsed, lessThan(const Duration(seconds: 60)));

    final pid = int.parse(await File(pidFile).readAsString());
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    var alive = await processIsAlive(pid);
    while (alive && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      alive = await processIsAlive(pid);
    }
    expect(alive, isFalse, reason: 'child $pid was left running');
  });
}

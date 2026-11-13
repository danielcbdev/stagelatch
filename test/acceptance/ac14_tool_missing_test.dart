import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  test('a missing tool is skipped and the commit succeeds', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.stagelatch(['install']);
    await repo.write('ok.txt', 'ok\n');
    await repo.stage('ok.txt');
    final git = await _program('git');
    final sh = await _program('sh');
    final separator = Platform.isWindows ? ';' : ':';
    final path = {p.dirname(git), p.dirname(sh)}.join(separator);

    final committed = await runGit(
      repo,
      ['commit', '-m', 'allowed'],
      env: {'PATH': path},
    );
    final log = await repo.git(['log', '--oneline', '-1']);

    expect(committed.code, 0, reason: committed.stderr);
    expect(committed.stderr, contains('stagelatch not found; skipping.'));
    expect(log, contains('allowed'));
  });
}

Future<String> _program(String name) async {
  final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
    name,
  ]);
  final text = result.stdout as String;
  return text.trim().split(RegExp(r'\r?\n')).first;
}

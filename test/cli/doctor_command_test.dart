@Tags(['git'])
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../support/temp_repo.dart';

void main() {
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
  });

  tearDown(() => repo.dispose());

  test('prints one line per probe, prefixed by its status', () async {
    final result = await repo.stagelatch(['doctor']);

    final lines = result.stdout.trimRight().split('\n');
    expect(lines.first, startsWith('ok    D1 git '));
    expect(lines[1], startsWith('ok    D2 Work tree: '));
    expect(lines.map((line) => line.substring(6, 8)).toSet(), {
      'D1',
      'D2',
      'D3',
      'D4',
      'D5',
      'D6',
      'D7',
      'D8',
    });
  });

  test('missing hooks are warnings, so the exit code is 0', () async {
    final result = await repo.stagelatch(['doctor']);

    expect(result.stdout, contains('warn  D4 pre-commit hook is missing.'));
    expect(result.exitCode, 0);
  });

  test('an invalid stagelatch.yaml fails D7 and exits 1', () async {
    await repo.stageContent('stagelatch.yaml', 'hooks: 3\n');

    final result = await repo.stagelatch(['doctor']);

    expect(result.stdout, contains('fail  D7 stagelatch.yaml: '));
    expect(result.exitCode, 1);
  });

  test('--reporter json prints the probes as one object', () async {
    final result = await repo.stagelatch(['doctor', '--reporter', 'json']);

    final json = jsonDecode(result.stdout) as Map<String, Object?>;
    expect(json.keys, ['schemaVersion', 'probes', 'exitCode']);
    final first = (json['probes']! as List<Object?>).first! as Map;
    expect(first.keys, ['id', 'status', 'message']);
    expect(first['id'], 'D1');
    expect(json['exitCode'], result.exitCode);
  });

  test('an unknown reporter is a usage error', () async {
    final result = await repo.stagelatch(['doctor', '--reporter', 'github']);

    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains('Unknown reporter "github". Expected console or json.'),
    );
  });
}

@Tags(['git'])
library;

import 'dart:convert';

import 'package:stagelatch/src/version.dart';
import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
  });

  tearDown(() => repo.dispose());

  test('--reporter json prints the JSON report of the run', () async {
    await repo.stageContent('pubspec.yaml', badPubspec);

    final result = await repo.stagelatch([
      'run',
      'pre-commit',
      '--reporter',
      'json',
    ]);

    expect(result.exitCode, 1);
    final report = jsonDecode(result.stdout) as Map<String, Object?>;
    expect(report['stagelatchVersion'], packageVersion);
    expect(report['entry'], 'pre-commit');
    expect(report['verdict'], 'fail');
    expect(
      ((report['findings']! as List<Object?>).single! as Map)['rule'],
      'pubspec/path-dependency',
    );
  });

  test('exit 64 prints the error object on stdout and the message on '
      'stderr', () async {
    final result = await repo.stagelatch(['run', 'x', '--reporter', 'json']);

    expect(result.exitCode, 64);
    expect(
      result.stdout,
      '{"schemaVersion":1,"error":{"kind":"usage","message":'
      r'"Unknown hook \"x\". Expected pre-commit or pre-push."},"exitCode":64}'
      '\n',
    );
    expect(
      result.stderr,
      'Unknown hook "x". Expected pre-commit or pre-push.\n',
    );
  });

  test('exit 78 prints the error object with kind config', () async {
    await repo.stageContent('stagelatch.yaml', 'hooks: 3\n');

    final result = await repo.stagelatch([
      'run',
      'pre-commit',
      '--reporter',
      'json',
    ]);

    expect(result.exitCode, 78);
    final error =
        (jsonDecode(result.stdout) as Map<String, Object?>)['error']!
            as Map<String, Object?>;
    expect(error['kind'], 'config');
    expect(result.stderr, contains(error['message']! as String));
  });

  test('--reporter github on run is a usage error naming the accepted '
      'values', () async {
    final result = await repo.stagelatch([
      'run',
      'pre-commit',
      '--reporter',
      'github',
    ]);

    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains('Unknown reporter "github". Expected console or json.'),
    );
  });
}

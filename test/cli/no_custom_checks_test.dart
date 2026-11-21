@Tags(['git'])
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../support/temp_repo.dart';

/// Minimal protocol-1 check that declares only `fixture/ok`.
const _checkSource = '''
import 'dart:convert';
import 'dart:io';

void main() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final message = jsonDecode(line) as Map<String, Object?>;
    switch (message['type']) {
      case 'init':
        stdout.writeln(jsonEncode({
          'type': 'ready',
          'protocol': 1,
          'rules': [
            {
              'id': 'fixture/ok',
              'summary': 'Always ok',
              'defaultSeverity': 'error',
            },
          ],
        }));
      case 'run':
        stdout
          ..writeln(jsonEncode({
            'type': 'finding',
            'rule': 'fixture/ok',
            'path': 'lib/a.dart',
            'line': 1,
            'column': 1,
            'message': 'hello from custom',
          }))
          ..writeln(jsonEncode({'type': 'done'}));
        return;
    }
  }
}
''';

void main() {
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
    await repo.write('tool/check.dart', _checkSource);
    await repo.write('lib/a.dart', 'void main() {}\n');
    await repo.write('stagelatch.yaml', '''
hooks:
  pre-commit: [fixture]
  pre-push: [fixture]
custom_checks:
  fixture:
    run: [dart, run, tool/check.dart]
    sources: [tool/check.dart]
''');
    await repo.stage('tool/check.dart');
    await repo.stage('lib/a.dart');
    await repo.stage('stagelatch.yaml');
    await repo.commit('custom check');
  });

  tearDown(() => repo.dispose());

  test(
    '--no-custom-checks on run skips the child and prints the notice',
    () async {
      final blocked = await repo.stagelatch(['run', 'pre-commit']);
      expect(blocked.exitCode, 1, reason: blocked.stdout + blocked.stderr);
      expect(blocked.stdout, contains('hello from custom'));

      final skipped = await repo.stagelatch([
        'run',
        'pre-commit',
        '--no-custom-checks',
        '--reporter',
        'json',
      ]);

      expect(skipped.exitCode, 0, reason: skipped.stdout + skipped.stderr);
      final json = jsonDecode(skipped.stdout) as Map<String, Object?>;
      expect(
        json['notices'],
        contains('Skipping custom checks (--no-custom-checks).'),
      );
      expect(skipped.stdout, isNot(contains('hello from custom')));
      expect(
        skipped.stderr,
        contains('Skipping custom checks (--no-custom-checks).'),
      );
    },
  );

  test(
    '--no-custom-checks on ci skips the child and prints the notice',
    () async {
      await repo.git(['switch', '-q', '-c', 'feature']);
      await repo.write('notes.txt', 'n\n');
      await repo.stage('notes.txt');
      await repo.commit('notes');

      final blocked = await repo.stagelatch(['ci', '--base', 'main']);
      expect(blocked.exitCode, 1, reason: blocked.stdout + blocked.stderr);

      final skipped = await repo.stagelatch([
        'ci',
        '--base',
        'main',
        '--no-custom-checks',
        '--reporter',
        'json',
      ]);

      expect(skipped.exitCode, 0, reason: skipped.stdout + skipped.stderr);
      final json = jsonDecode(skipped.stdout) as Map<String, Object?>;
      expect(
        json['notices'],
        contains('Skipping custom checks (--no-custom-checks).'),
      );
      expect(skipped.stdout, isNot(contains('hello from custom')));
    },
  );

  test(
    'with --no-custom-checks, ignore under a configured custom id is accepted',
    () async {
      await repo.write(
        'lib/a.dart',
        '// stagelatch:ignore fixture/anything\nvoid main() {}\n',
      );
      await repo.stage('lib/a.dart');

      final result = await repo.stagelatch([
        'run',
        'pre-commit',
        '--no-custom-checks',
        '--reporter',
        'json',
      ]);

      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
      final json = jsonDecode(result.stdout) as Map<String, Object?>;
      final findings = json['findings']! as List<Object?>;
      expect(
        findings.where(
          (f) => (f! as Map)['rule'] == 'stagelatch/invalid-ignore',
        ),
        isEmpty,
      );
    },
  );

  test('with --no-custom-checks, an unknown check prefix still yields '
      'invalid-ignore', () async {
    await repo.write(
      'lib/a.dart',
      '// stagelatch:ignore totally-unknown/rule\nvoid main() {}\n',
    );
    await repo.stage('lib/a.dart');

    final result = await repo.stagelatch([
      'run',
      'pre-commit',
      '--no-custom-checks',
      '--reporter',
      'json',
    ]);

    final json = jsonDecode(result.stdout) as Map<String, Object?>;
    final findings = json['findings']! as List<Object?>;
    expect(
      findings.any((f) {
        final map = f! as Map<Object?, Object?>;
        return map['rule'] == 'stagelatch/invalid-ignore' &&
            map['message'].toString().contains('totally-unknown/rule');
      }),
      isTrue,
      reason: result.stdout,
    );
  });

  test(
    'with the check active, an undeclared rule yields invalid-ignore',
    () async {
      await repo.write(
        'lib/a.dart',
        '// stagelatch:ignore fixture/not-declared\nvoid main() {}\n',
      );
      await repo.stage('lib/a.dart');

      final result = await repo.stagelatch([
        'run',
        'pre-commit',
        '--reporter',
        'json',
      ]);

      final json = jsonDecode(result.stdout) as Map<String, Object?>;
      final findings = json['findings']! as List<Object?>;
      expect(
        findings.any((f) {
          final map = f! as Map<Object?, Object?>;
          return map['rule'] == 'stagelatch/invalid-ignore' &&
              map['message'].toString().contains('fixture/not-declared');
        }),
        isTrue,
        reason: result.stdout,
      );
    },
  );
}

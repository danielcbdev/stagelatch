import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/config/custom_check_config.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_check_catalog.dart';
import '../../support/fake_snapshot_files.dart';
import '../../support/fake_working_tree.dart';

final _toolVersion = Version.parse('0.3.0');

Future<LoadedConfig> _load(String yaml) =>
    ConfigLoader(const StructuredDocuments(), FakeWorkingTree()).load(
      FakeSnapshotFiles({'stagelatch.yaml': yaml}),
      toolVersion: _toolVersion,
      catalog: FakeCheckCatalog.full(),
    );

Future<Config> _config(String yaml) async => (await _load(yaml)).config;

Future<ConfigException> _error(String yaml) async {
  try {
    await _load(yaml);
  } on ConfigException catch (error) {
    return error;
  }
  fail('Expected a ConfigException for:\n$yaml');
}

void main() {
  group('custom_checks', () {
    test('loads a well-formed entry with inferred sources', () async {
      final config = await _config('''
custom_checks:
  team:
    run: [dart, run, tool/stagelatch_checks.dart]
    rules:
      no-print: error
    severity: high
''');

      expect(config.customChecks, hasLength(1));
      final check = config.customChecks.single;
      expect(check, isA<CustomCheckConfig>());
      expect(check.id, 'team');
      expect(check.run, ['dart', 'run', 'tool/stagelatch_checks.dart']);
      expect(check.timeout, const Duration(seconds: 60));
      expect(check.sources, [RepoPath('tool/stagelatch_checks.dart')]);
      expect(check.rules, {'no-print': RuleLevel.error});
      expect(check.settings, {'severity': 'high'});
      expect(config.rules[const RuleId('team', 'no-print')], RuleLevel.error);
    });

    test('default timeout is 60s; explicit timeout is parsed', () async {
      final config = await _config('''
custom_checks:
  a:
    run: [tool/a.dart]
  b:
    run: [tool/b.dart]
    timeout: 90s
''');

      expect(config.customChecks[0].timeout, const Duration(seconds: 60));
      expect(config.customChecks[1].timeout, const Duration(seconds: 90));
    });

    test('explicit sources are kept', () async {
      final config = await _config('''
custom_checks:
  team:
    run: [python, tool/x.py]
    sources: [tool/x.py, tool/lib.py]
''');

      expect(config.customChecks.single.sources, [
        RepoPath('tool/x.py'),
        RepoPath('tool/lib.py'),
      ]);
    });

    test('shadowing a built-in check id is a config error', () async {
      final error = await _error('''
custom_checks:
  pubspec:
    run: [dart, run, tool/x.dart]
''');

      expect(
        error.message,
        'custom_checks."pubspec" shadows the built-in check "pubspec".',
      );
    });

    test('run must be a non-empty list of strings', () async {
      expect(
        (await _error('''
custom_checks:
  team:
    run: []
''')).message,
        '"custom_checks.team.run" must be a non-empty list of strings, '
        'found an empty list.',
      );
      expect(
        (await _error('''
custom_checks:
  team:
    run: dart
''')).message,
        '"custom_checks.team.run" must be a non-empty list of strings, '
        'found a string.',
      );
      expect(
        (await _error('''
custom_checks:
  team: {}
''')).message,
        '"custom_checks.team.run" must be a non-empty list of strings, '
        'found null.',
      );
    });

    test('explicit empty sources is a config error', () async {
      final error = await _error('''
custom_checks:
  team:
    run: [dart, run, tool/x.dart]
    sources: []
''');

      expect(
        error.message,
        '"custom_checks.team.sources" must be a non-empty list of '
        'repository paths when set, found an empty list.',
      );
    });

    test(
      'omitted sources when run is not inferable is a config error',
      () async {
        expect(
          (await _error('''
custom_checks:
  team:
    run: [python, tool/x.py]
''')).message,
          'custom_checks."team": cannot infer a non-empty source closure '
          'from "run"; set "custom_checks.team.sources" to a non-empty list.',
        );
        expect(
          (await _error('''
custom_checks:
  team:
    run: [dart, run, package:some_pkg/bin/check.dart]
''')).message,
          'custom_checks."team": cannot infer a non-empty source closure '
          'from "run"; set "custom_checks.team.sources" to a non-empty list.',
        );
      },
    );

    test('selector and root rules may name a custom rule', () async {
      final config = await _config('''
hooks:
  pre-push: [team, team/no-print]
rules:
  team/no-print: warning
  team/other: off
custom_checks:
  team:
    run: [dart, run, tool/x.dart]
    rules:
      no-print: error
''');

      expect(config.hooks['pre-push']!.map((s) => s.toString()).toList(), [
        'team',
        'team/no-print',
      ]);
      expect(config.rules[const RuleId('team', 'no-print')], RuleLevel.warning);
      expect(config.rules[const RuleId('team', 'other')], RuleLevel.off);
    });

    test('unknown custom rules are deferred, not rejected at load', () async {
      final config = await _config('''
hooks:
  pre-push: [team/never-declared]
rules:
  team/also-unknown: warning
custom_checks:
  team:
    run: [tool/x.dart]
''');

      expect(
        config.hooks['pre-push']!.single.toString(),
        'team/never-declared',
      );
      expect(
        config.rules[const RuleId('team', 'also-unknown')],
        RuleLevel.warning,
      );
    });

    test('rule names under custom_checks may not contain a slash', () async {
      final error = await _error('''
custom_checks:
  team:
    run: [tool/x.dart]
    rules:
      team/no-print: error
''');

      expect(
        error.message,
        'Rule name "team/no-print" under custom_checks."team" '
        'must not contain "/".',
      );
    });

    test(
      'additional keys land in settings as JSON-compatible values',
      () async {
        final config = await _config('''
custom_checks:
  team:
    run: [tool/x.dart]
    flag: true
    count: 3
    nested:
      a: b
    list: [1, two]
''');

        expect(config.customChecks.single.settings, {
          'flag': true,
          'count': 3,
          'nested': {'a': 'b'},
          'list': [1, 'two'],
        });
      },
    );

    test('invalid timeout and invalid source path are rejected', () async {
      expect(
        (await _error('''
custom_checks:
  team:
    run: [tool/x.dart]
    timeout: 0s
''')).message,
        'Invalid duration "0s" in "custom_checks.team.timeout".',
      );
      expect(
        (await _error('''
custom_checks:
  team:
    run: [python, tool/x.py]
    sources: [/abs/x.py]
''')).message,
        'Invalid path "/abs/x.py" in "custom_checks.team.sources".',
      );
    });
  });
}

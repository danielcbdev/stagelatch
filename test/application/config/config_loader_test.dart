import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/check_catalog.dart';
import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/config/default_hooks.dart';
import 'package:stagelatch/src/application/config/settings.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_check_catalog.dart';
import '../../support/fake_snapshot_files.dart';
import '../../support/fake_working_tree.dart';

final _toolVersion = Version.parse('0.1.0-dev.1');

Future<LoadedConfig> _load({
  String? staged,
  String? onDisk,
  CheckCatalog? catalog,
  Version? toolVersion,
}) =>
    ConfigLoader(
      const StructuredDocuments(),
      FakeWorkingTree({'stagelatch.yaml': ?onDisk}),
    ).load(
      FakeSnapshotFiles({'stagelatch.yaml': ?staged}),
      toolVersion: toolVersion ?? _toolVersion,
      catalog: catalog ?? FakeCheckCatalog.full(),
    );

Future<Config> _config(String yaml) async => (await _load(staged: yaml)).config;

/// The error a staged config is expected to produce.
Future<ConfigException> _error(String yaml) async {
  try {
    await _load(staged: yaml);
  } on ConfigException catch (error) {
    return error;
  }
  fail('Expected a ConfigException for:\n$yaml');
}

List<String> _selectors(Config config, String hook) => [
  for (final selector in config.hooks[hook]!) selector.toString(),
];

/// The full example of docs/specs/config.md, section 2.
const _specExample = '''
min_version: 0.1.0

hooks:
  pre-commit: [format, analyze, codegen, pubspec, l10n, assets, sensitive-files, tests/solo, tests/new-skip]
  pre-push: [analyze, tests/affected]

rules:
  l10n/unused-key: warning
  tests/new-skip: warning
  pubspec/unpinned-git: off

exclude: [lib/generated/**]

# sdk_path: .fvm/flutter_sdk

time_budget: 2s

format:
  fix: true

analyze:
  scope: affected
  fail_on: [error, warning]

codegen:
  generated_files_committed: true

pubspec:
  monotonic_build_number: [release/*]

assets:
  max_file_size: 500KB
  ignore: [assets/videos/**]

baseline: .stagelatch/baseline.json
''';

void main() {
  group('defaults', () {
    test('no config anywhere yields the documented defaults', () async {
      final loaded = await _load();
      final config = loaded.config;

      expect(loaded.notices, isEmpty);
      expect(config.minVersion, isNull);
      expect(config.rules, isEmpty);
      expect(config.exclude, isEmpty);
      expect(config.sdkPath, isNull);
      expect(config.timeBudget, const Duration(seconds: 2));
      expect(config.baselinePath, RepoPath('.stagelatch/baseline.json'));
      expect(config.settings<FormatSettings>().fix, isTrue);
      expect(config.settings<AnalyzeSettings>().scope, AnalyzeScope.affected);
      expect(config.settings<AnalyzeSettings>().failOn, {
        DiagnosticSeverity.error,
        DiagnosticSeverity.warning,
      });
      expect(
        config.settings<CodegenSettings>().generatedFilesCommitted,
        isTrue,
      );
      expect(config.settings<CodegenSettings>().generatedSuffixes, [
        '.g.dart',
        '.freezed.dart',
      ]);
      expect(config.settings<PubspecSettings>().monotonicBuildNumber, isEmpty);
      expect(config.settings<PubspecSettings>().requireSha, isFalse);
      expect(config.settings<AssetsSettings>().maxFileSize, 512000);
      expect(config.settings<AssetsSettings>().roots, [RepoPath('assets')]);
      expect(config.settings<AssetsSettings>().ignore, isEmpty);
      expect(config.settings<TestsSettings>().functions, [
        'test',
        'testWidgets',
        'group',
      ]);
    });

    test('default hooks hold only what the running version has', () async {
      final loaded = await _load(
        catalog: FakeCheckCatalog(rules: {'pubspec/path-dependency'}),
      );

      expect(_selectors(loaded.config, preCommitHook), ['pubspec']);
      expect(_selectors(loaded.config, prePushHook), isEmpty);
      expect(_selectors(loaded.config, ciHook), ['pubspec']);
    });

    test('an empty file is the same as no file', () async {
      final config = await _config('');

      expect(config.timeBudget, const Duration(seconds: 2));
      expect(_selectors(config, prePushHook), ['analyze', 'tests/affected']);
    });

    test('asking for settings of an unknown type is a programming error', () {
      expect(
        () async => (await _load()).config.settings<String>(),
        throwsStateError,
      );
    });
  });

  group('a valid config', () {
    test('the full example of the spec loads', () async {
      // The example requires 0.1.0, which the default test version, a
      // pre-release of it, does not satisfy.
      final loaded = await _load(
        staged: _specExample,
        toolVersion: Version.parse('0.1.0'),
      );
      final config = loaded.config;

      expect(config.minVersion, Version.parse('0.1.0'));
      expect(_selectors(config, preCommitHook), hasLength(9));
      expect(_selectors(config, prePushHook), ['analyze', 'tests/affected']);
      expect(config.rules, {
        const RuleId('l10n', 'unused-key'): RuleLevel.warning,
        const RuleId('tests', 'new-skip'): RuleLevel.warning,
        const RuleId('pubspec', 'unpinned-git'): RuleLevel.off,
      });
      expect(config.exclude.single.pattern, 'lib/generated/**');
      expect(
        config.settings<PubspecSettings>().monotonicBuildNumber.single.pattern,
        'release/*',
      );
      expect(
        config.settings<AssetsSettings>().ignore.single.pattern,
        'assets/videos/**',
      );
    });

    test('reads every parameter', () async {
      final config = await _config('''
sdk_path: .fvm/flutter_sdk
time_budget: 750ms
baseline: tool/baseline.json
format:
  fix: false
analyze:
  scope: all
  fail_on: [error, warning, info]
codegen:
  generated_files_committed: false
  generated_suffixes: [.g.dart, .config.dart]
pubspec:
  require_sha: true
assets:
  max_file_size: 2MB
  roots: [assets/, packages/ui/assets]
tests:
  functions: [test, blocTest]
''');

      expect(config.sdkPath, '.fvm/flutter_sdk');
      expect(config.timeBudget, const Duration(milliseconds: 750));
      expect(config.baselinePath, RepoPath('tool/baseline.json'));
      expect(config.settings<FormatSettings>().fix, isFalse);
      expect(config.settings<AnalyzeSettings>().scope, AnalyzeScope.all);
      expect(
        config.settings<AnalyzeSettings>().failOn,
        DiagnosticSeverity.values.toSet(),
      );
      expect(
        config.settings<CodegenSettings>().generatedFilesCommitted,
        isFalse,
      );
      expect(config.settings<CodegenSettings>().generatedSuffixes, [
        '.g.dart',
        '.config.dart',
      ]);
      expect(config.settings<PubspecSettings>().requireSha, isTrue);
      expect(config.settings<AssetsSettings>().maxFileSize, 2 * 1024 * 1024);
      expect(config.settings<AssetsSettings>().roots, [
        RepoPath('assets'),
        RepoPath('packages/ui/assets'),
      ]);
      expect(config.settings<TestsSettings>().functions, ['test', 'blocTest']);
    });

    test('an explicit hook list replaces the default', () async {
      final config = await _config('hooks:\n  pre-commit: [pubspec]\n');

      expect(_selectors(config, preCommitHook), ['pubspec']);
      expect(_selectors(config, prePushHook), ['analyze', 'tests/affected']);
      expect(_selectors(config, ciHook), [
        'pubspec',
        'analyze',
        'tests/affected',
      ]);
    });

    test('an explicit ci list replaces the union', () async {
      final config = await _config('hooks:\n  ci: [analyze]\n');

      expect(_selectors(config, ciHook), ['analyze']);
    });

    test('a bare off is the off level', () async {
      final config = await _config(
        'rules:\n  pubspec/path-dependency: off\n  tests/solo: error\n',
      );

      expect(config.rules, {
        const RuleId('pubspec', 'path-dependency'): RuleLevel.off,
        const RuleId('tests', 'solo'): RuleLevel.error,
      });
    });

    test('any rule name is accepted under a dynamic check', () async {
      final config = await _config('rules:\n  analyze/unused_import: off\n');

      expect(
        config.rules.keys.single,
        const RuleId('analyze', 'unused_import'),
      );
    });

    test('globs match repository paths with forward slashes', () async {
      final config = await _config('exclude: ["lib/generated/**", "*.g.dart"]');

      expect(config.exclude[0].matches('lib/generated/a/b.dart'), isTrue);
      expect(config.exclude[0].matches('lib/src/a.dart'), isFalse);
      expect(config.exclude[1].matches('model.g.dart'), isTrue);
      expect(config.exclude[1].matches('Model.G.dart'), isFalse);
    });

    test('a section left empty keeps its defaults', () async {
      final config = await _config('format:\nexclude:\nrules:\nhooks:\n');

      expect(config.settings<FormatSettings>().fix, isTrue);
      expect(config.exclude, isEmpty);
      expect(config.rules, isEmpty);
      expect(_selectors(config, prePushHook), ['analyze', 'tests/affected']);
    });
  });

  group('where the config comes from (ADR-0015)', () {
    test('the snapshot wins over the working tree', () async {
      final loaded = await _load(
        staged: 'time_budget: 1s\n',
        onDisk: 'time_budget: 9s\n',
      );

      expect(loaded.config.timeBudget, const Duration(seconds: 1));
      expect(loaded.notices, isEmpty);
    });

    test('a config only in the working tree is used, with a notice', () async {
      final loaded = await _load(onDisk: 'time_budget: 9s\n');

      expect(loaded.config.timeBudget, const Duration(seconds: 9));
      expect(loaded.notices, [
        'stagelatch.yaml is not staged; using the working tree copy.',
      ]);
    });

    test('an invalid working tree copy is still an error', () {
      expect(() => _load(onDisk: 'nope: 1\n'), throwsA(isA<ConfigException>()));
    });
  });

  group('validation', () {
    test('an unknown key reports its position and parent', () async {
      final error = await _error('pubspec:\n  forbid: []\n');

      expect(
        error.toString(),
        'stagelatch.yaml:2:3: Unknown key "forbid" under "pubspec".',
      );
    });

    test('an unknown key at the top level', () async {
      final error = await _error('time_budget: 2s\nfrmat:\n  fix: true\n');

      expect(
        error.toString(),
        'stagelatch.yaml:2:1: Unknown key "frmat" at the top level.',
      );
    });

    test('the first problem in document order is the one reported', () async {
      final error = await _error('bogus: 1\ntime_budget: never\n');

      expect(error.message, 'Unknown key "bogus" at the top level.');
    });

    test('a root that is not a map', () async {
      final error = await _error('- a\n- b\n');

      expect(
        error.toString(),
        'stagelatch.yaml:1:1: Expected a map at the top level.',
      );
    });

    test('invalid YAML reports the parser position', () async {
      final error = await _error('exclude: [a, b\n');

      expect(error.toString(), startsWith('stagelatch.yaml:2:1: '));
      expect(error.message, endsWith('.'));
    });

    test('a duplicate key', () async {
      final error = await _error('exclude: []\nexclude: []\n');

      expect(error.toString(), 'stagelatch.yaml:2:1: Duplicate mapping key.');
    });

    test('a wrong type names the key and both types', () async {
      expect(
        (await _error('format:\n  fix: "yes"\n')).toString(),
        'stagelatch.yaml:2:8: "format.fix" must be a boolean, found a string.',
      );
      expect(
        (await _error('hooks: [pubspec]\n')).message,
        '"hooks" must be a map, found a list.',
      );
      expect(
        (await _error('exclude: lib/**\n')).message,
        '"exclude" must be a list, found a string.',
      );
      expect(
        (await _error('exclude: [1]\n')).message,
        '"exclude" must be a list of strings, found a number.',
      );
      expect(
        (await _error('baseline: [a]\n')).message,
        '"baseline" must be a string, found a list.',
      );
      expect(
        (await _error('format: true\n')).message,
        '"format" must be a map, found a boolean.',
      );
    });

    test('an unknown hook name', () async {
      final error = await _error('hooks:\n  post-merge: [pubspec]\n');

      expect(
        error.toString(),
        'stagelatch.yaml:2:3: Unknown hook "post-merge". '
        'Expected pre-commit, pre-push or ci.',
      );
    });

    test('an unknown check in a selector', () async {
      final error = await _error('hooks:\n  pre-commit: [pubspec, nope]\n');

      expect(
        error.toString(),
        'stagelatch.yaml:2:25: Unknown check "nope" in hooks.pre-commit.',
      );
    });

    test('a selector that is not check or check/rule', () async {
      final error = await _error('hooks:\n  pre-push: [a/b/c]\n');

      expect(error.message, 'Invalid selector "a/b/c" in "hooks.pre-push".');
    });

    test('an unknown rule in a selector', () async {
      final error = await _error('hooks:\n  pre-commit: [tests/nope]\n');

      expect(error.message, 'Unknown rule "tests/nope".');
    });

    test('an unknown rule in the rules map', () async {
      expect(
        (await _error('rules:\n  pubspec/nope: off\n')).toString(),
        'stagelatch.yaml:2:3: Unknown rule "pubspec/nope".',
      );
      expect(
        (await _error('rules:\n  not a rule: off\n')).message,
        'Unknown rule "not a rule".',
      );
      expect(
        (await _error('rules:\n  nocheck/x: off\n')).message,
        'Unknown rule "nocheck/x".',
      );
    });

    test('an invalid level, including a bare true', () async {
      const expected =
          'Level of "pubspec/path-dependency" must be error, warning or off.';

      expect(
        (await _error('rules:\n  pubspec/path-dependency: fatal\n')).message,
        expected,
      );
      expect(
        (await _error('rules:\n  pubspec/path-dependency: true\n')).message,
        expected,
      );
    });

    test('an invalid glob', () async {
      expect(
        (await _error('exclude: ["lib/[a"]\n')).message,
        'Invalid glob "lib/[a" in "exclude".',
      );
      expect(
        (await _error('assets:\n  ignore: ["{a"]\n')).message,
        'Invalid glob "{a" in "assets.ignore".',
      );
    });

    test('an invalid size, including a bare number', () async {
      expect(
        (await _error('assets:\n  max_file_size: 500\n')).message,
        'Invalid size "500" in "assets.max_file_size".',
      );
      expect(
        (await _error('assets:\n  max_file_size: 1GB\n')).message,
        'Invalid size "1GB" in "assets.max_file_size".',
      );
    });

    test('an invalid duration', () async {
      expect(
        (await _error('time_budget: 0s\n')).toString(),
        'stagelatch.yaml:1:14: Invalid duration "0s" in "time_budget".',
      );
      expect(
        (await _error('time_budget: 2\n')).message,
        'Invalid duration "2" in "time_budget".',
      );
    });

    test('an invalid version', () async {
      expect(
        (await _error('min_version: 1.0\n')).message,
        'Invalid version "1.0" in "min_version".',
      );
    });

    test('an invalid scope and an invalid severity', () async {
      expect(
        (await _error('analyze:\n  scope: everything\n')).message,
        'Invalid scope "everything" in "analyze.scope".',
      );
      expect(
        (await _error('analyze:\n  fail_on: [error, hint]\n')).message,
        'Invalid severity "hint" in "analyze.fail_on".',
      );
    });

    test('an asset root or baseline that leaves the repository', () async {
      expect(
        (await _error('assets:\n  roots: [../assets]\n')).message,
        'Invalid directory "../assets" in "assets.roots".',
      );
      expect(
        (await _error('baseline: /abs/baseline.json\n')).message,
        'Invalid path "/abs/baseline.json" in "baseline".',
      );
    });

    test('a test function that is not an identifier', () async {
      expect(
        (await _error('tests:\n  functions: [test, my-test]\n')).message,
        'Invalid identifier "my-test" in "tests.functions".',
      );
    });

    test('custom_checks is reserved for 1.0.0', () async {
      final error = await _error('custom_checks: {}\n');

      expect(error.message, 'custom_checks requires stagelatch >= 1.0.0.');
    });
  });

  group('min_version', () {
    test('an older tool is told to upgrade', () async {
      final error = await _error('min_version: 9.0.0\n');

      expect(
        error.message,
        'This repository requires stagelatch >= 9.0.0; you have 0.1.0-dev.1. '
        'Run: dart pub global activate stagelatch',
      );
    });

    test('is checked before anything else in the file', () async {
      final error = await _error(
        'hooks:\n  pre-commit: [from-the-future]\nmin_version: 9.0.0\n',
      );

      expect(error.message, startsWith('This repository requires stagelatch'));
    });

    test('an equal or older requirement passes', () async {
      expect(
        (await _config('min_version: 0.1.0-dev.1\n')).minVersion,
        isNotNull,
      );
      expect((await _config('min_version: 0.0.1\n')).minVersion, isNotNull);
    });

    test('a pre-release of the required version is too old', () async {
      final error = await _error('min_version: 0.1.0\n');

      expect(error.message, contains('>= 0.1.0; you have 0.1.0-dev.1.'));
    });
  });
}

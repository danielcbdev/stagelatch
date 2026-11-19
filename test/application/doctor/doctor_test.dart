import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/doctor/doctor.dart';
import 'package:stagelatch/src/application/doctor/probe_result.dart';
import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/hooks/hook_name.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/ports/doctor_probes.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_git_repository.dart';
import '../../support/fake_hook_store.dart';
import '../../support/fake_sdk_locator.dart';
import '../../support/fake_working_tree.dart';

const _managed = '#!/bin/sh\n# stagelatch:managed\n';

final class _Probes implements DoctorProbes {
  new({
    this.git = 'git version 2.56.0',
    this.onPath = const {},
    this.activated = false,
    this.configs = const {},
    this.throwOnGit = false,
  });

  final String? git;
  final Map<String, String> onPath;
  final bool activated;
  final Set<String> configs;
  final bool throwOnGit;

  @override
  Future<String?> gitVersion() async {
    if (throwOnGit) throw StateError('boom\nsecond line');
    return git;
  }

  @override
  Future<String?> resolveOnPath(String name) async => onPath[name];

  @override
  Future<bool> globallyActivated() async => activated;

  @override
  Future<bool> packageConfigExists(RepoPath? packageRoot) async =>
      configs.contains(packageRoot?.value ?? '');
}

RepoLayout _layout({String hooksDir = '/repo/.git/hooks'}) => RepoLayout(
  root: '/repo',
  gitDir: '/repo/.git',
  commonDir: '/repo/.git',
  hooksDir: hooksDir,
  branch: 'main',
  mergeInProgress: false,
  rebaseInProgress: false,
  shallow: false,
);

Future<List<ProbeResult>> _run({
  Map<String, Object> index = const {},
  Map<String, String> worktree = const {},
  RepoLayout? layout,
  Map<HookName, String> hooks = const {},
  _Probes? probes,
  FakeSdkLocator? sdk,
  String version = '0.1.0',
}) {
  final store = FakeHookStore();
  store.files.addAll(hooks);
  final tree = FakeWorkingTree(worktree);
  return Doctor(
    git: FakeGitRepository(index: index, layout: layout ?? _layout()),
    hooks: store,
    loader: ConfigLoader(const StructuredDocuments(), tree),
    documents: const StructuredDocuments(),
    worktree: tree,
    catalog: CheckRegistry(const []),
    sdk: sdk ?? FakeSdkLocator(),
    environment: Environment(
      workingDirectory: '/repo',
      variables: const {'SECRET_TOKEN': 'do-not-print'},
      stdoutIsTerminal: false,
      stdinIsTerminal: false,
    ),
    probes: probes ?? _Probes(),
    toolVersion: Version.parse(version),
  ).run();
}

ProbeResult _probe(List<ProbeResult> results, String id) =>
    results.firstWhere((result) => result.id == id);

(ProbeStatus, String) _pair(List<ProbeResult> results, String id) {
  final probe = _probe(results, id);
  return (probe.status, probe.message);
}

void main() {
  test('a healthy repository passes every probe, in order', () async {
    final results = await _run(
      index: {
        'stagelatch.yaml': 'min_version: 0.1.0\n',
        'pubspec.yaml': 'name: app\n',
      },
      hooks: {HookName.preCommit: _managed, HookName.prePush: _managed},
      probes: _Probes(
        onPath: {'stagelatch': '/home/u/.pub-cache/bin/stagelatch'},
        configs: {''},
      ),
    );

    expect(
      [for (final r in results) '${r.status.name} ${r.id} ${r.message}'],
      [
        'ok D1 git 2.56.0',
        'ok D2 Work tree: /repo',
        'ok D3 Hooks directory: /repo/.git/hooks',
        'ok D4 pre-commit hook is managed by stagelatch.',
        'ok D4 pre-push hook is managed by stagelatch.',
        'ok D5 stagelatch on PATH: /home/u/.pub-cache/bin/stagelatch',
        'ok D6 stagelatch 0.1.0 satisfies min_version 0.1.0.',
        'ok D7 stagelatch.yaml is valid.',
        'ok D8 Dart SDK 3.13.0 at /sdk (PATH)',
        'ok D9 .dart_tool/package_config.json found.',
      ],
    );
  });

  group('D1', () {
    test('git missing fails', () async {
      expect(_pair(await _run(probes: _Probes(git: null)), 'D1'), (
        ProbeStatus.fail,
        'git not found on PATH.',
      ));
    });

    test('git older than 2.30 fails', () async {
      final results = await _run(probes: _Probes(git: 'git version 2.29.3'));

      expect(_pair(results, 'D1'), (
        ProbeStatus.fail,
        'git 2.29.3 is older than 2.30.',
      ));
    });

    test('a vendor suffix is ignored', () async {
      final results = await _run(
        probes: _Probes(git: 'git version 2.39.5 (Apple Git-154)'),
      );

      expect(_pair(results, 'D1'), (ProbeStatus.ok, 'git 2.39.5'));
    });
  });

  test('D3 warns when core.hooksPath points elsewhere', () async {
    final results = await _run(layout: _layout(hooksDir: '/repo/.husky'));

    expect(_pair(results, 'D3'), (
      ProbeStatus.warn,
      'Hooks directory: /repo/.husky (core.hooksPath is set)',
    ));
  });

  test('D4 warns for a missing hook and for a third-party hook', () async {
    final results = await _run(
      hooks: {HookName.preCommit: '#!/bin/sh\nlint-staged\n'},
    );

    expect(
      [
        for (final r in results)
          if (r.id == 'D4') (r.status, r.message),
      ],
      [
        (ProbeStatus.warn, 'pre-commit hook is not managed by stagelatch.'),
        (ProbeStatus.warn, 'pre-push hook is missing. Run: stagelatch install'),
      ],
    );
  });

  group('D5', () {
    test('only the dart pub global run fallback works', () async {
      expect(_pair(await _run(probes: _Probes(activated: true)), 'D5'), (
        ProbeStatus.warn,
        'stagelatch is not on PATH; hooks fall back to dart pub global run.',
      ));
    });

    test('not installed at all', () async {
      expect(_pair(await _run(), 'D5'), (
        ProbeStatus.warn,
        'stagelatch is not installed; hooks skip without blocking.',
      ));
    });
  });

  group('D6 and D7', () {
    test('an older tool fails D6, and D7 reports the config error', () async {
      final results = await _run(
        index: {'stagelatch.yaml': 'min_version: 9.0.0\n'},
      );

      expect(_pair(results, 'D6'), (
        ProbeStatus.fail,
        'stagelatch 0.1.0 is older than min_version 9.0.0.',
      ));
      expect(_probe(results, 'D7').status, ProbeStatus.fail);
      expect(_probe(results, 'D7').message, startsWith('stagelatch.yaml: '));
    });

    test('no min_version and no stagelatch.yaml', () async {
      final results = await _run();

      expect(_pair(results, 'D6'), (
        ProbeStatus.ok,
        'stagelatch 0.1.0; no min_version.',
      ));
      expect(_pair(results, 'D7'), (
        ProbeStatus.ok,
        'No stagelatch.yaml; defaults apply.',
      ));
    });

    test('an invalid config fails D7 with its message', () async {
      final results = await _run(index: {'stagelatch.yaml': 'hooks: 3\n'});

      expect(_probe(results, 'D7').status, ProbeStatus.fail);
      expect(
        _probe(results, 'D7').message,
        startsWith('stagelatch.yaml: stagelatch.yaml:1:'),
      );
    });

    test('a config only in the working tree is valid', () async {
      final results = await _run(worktree: {'stagelatch.yaml': 'hooks: {}\n'});

      expect(_pair(results, 'D7'), (
        ProbeStatus.ok,
        'stagelatch.yaml is valid.',
      ));
    });
  });

  test('D8 reports the SDK, or fails with the locator message', () async {
    final ok = await _run(
      sdk: FakeSdkLocator(
        sdk: const ResolvedSdk(
          root: '/fvm/3.29.0/bin/cache/dart-sdk',
          dartExecutable: '/x/dart',
          flutterExecutable: '/x/flutter',
          version: '3.7.0',
          source: SdkSource.fvm,
        ),
      ),
    );
    final failed = await _run(
      sdk: FakeSdkLocator(
        error: const ConfigException(
          'No Dart SDK found. Install Dart or set sdk_path.',
        ),
      ),
    );

    expect(_pair(ok, 'D8'), (
      ProbeStatus.ok,
      'Dart SDK 3.7.0 at /fvm/3.29.0/bin/cache/dart-sdk (fvm)',
    ));
    expect(_pair(failed, 'D8'), (
      ProbeStatus.fail,
      'No Dart SDK found. Install Dart or set sdk_path.',
    ));
  });

  test('D9 has one line per package', () async {
    final results = await _run(
      index: {
        'pubspec.yaml': 'name: app\n',
        'packages/ui/pubspec.yaml': 'name: ui\n',
      },
      probes: _Probes(configs: {'packages/ui'}),
    );

    expect(
      [
        for (final r in results)
          if (r.id == 'D9') (r.status, r.message),
      ],
      [
        (
          ProbeStatus.warn,
          'Missing .dart_tool/package_config.json. Run: dart pub get',
        ),
        (ProbeStatus.ok, 'packages/ui/.dart_tool/package_config.json found.'),
      ],
    );
  });

  test(
    'a probe that throws becomes a fail result and the others still run',
    () async {
      final results = await _run(probes: _Probes(throwOnGit: true));

      expect(_pair(results, 'D1'), (
        ProbeStatus.fail,
        'Probe failed: Bad state: boom',
      ));
      expect(_probe(results, 'D2').status, ProbeStatus.ok);
    },
  );

  test('no environment variable value is printed', () async {
    final results = await _run();

    expect(results.every((r) => !r.message.contains('do-not-print')), isTrue);
  });

  test('exit code is 1 when any probe fails, else 0', () {
    expect(doctorExitCode(const [ProbeResult('D1', ProbeStatus.warn, 'x')]), 0);
    expect(
      doctorExitCode(const [
        ProbeResult('D1', ProbeStatus.ok, 'x'),
        ProbeResult('D2', ProbeStatus.fail, 'y'),
      ]),
      1,
    );
  });

  test('the console line pads the status to six characters', () {
    expect(
      const ProbeResult('D1', ProbeStatus.ok, 'git 2.56.0').toConsoleLine(),
      'ok    D1 git 2.56.0',
    );
    expect(
      const ProbeResult('D4', ProbeStatus.warn, 'a\nb').toConsoleLine(),
      'warn  D4 a b',
    );
  });
}

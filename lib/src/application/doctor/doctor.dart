/// `stagelatch doctor`: why the hooks or the gate might not behave
/// (docs/specs/cli.md, section 3.6).
library;

import 'dart:typed_data';

import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/check_catalog.dart';
import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/config/custom_check_config.dart';
import 'package:stagelatch/src/application/doctor/probe_result.dart';
import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/hooks/hook_name.dart';
import 'package:stagelatch/src/application/packages/package_map_builder.dart';
import 'package:stagelatch/src/application/ports/doctor_probes.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/application/ports/hook_store.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/application/ports/working_tree.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// Runs probes D1 to D10 in order. Each probe is independent: one that
/// throws becomes a `fail` line and the others still run.
final class Doctor {
  /// Creates the doctor.
  new({
    required this._git,
    required this._hooks,
    required this._loader,
    required this._documents,
    required this._worktree,
    required this._catalog,
    required this._sdk,
    required this._environment,
    required this._probes,
    required this._toolVersion,
  });

  final GitRepository _git;
  final HookStore _hooks;
  final ConfigLoader _loader;
  final Documents _documents;
  final WorkingTree _worktree;
  final CheckCatalog _catalog;
  final SdkLocator _sdk;
  final Environment _environment;
  final DoctorProbes _probes;
  final Version _toolVersion;

  static final RepoPath _configPath = RepoPath('stagelatch.yaml');

  /// Every probe's result, in order.
  Future<List<ProbeResult>> run() async {
    Config? config;
    final probes = <(String, Future<List<ProbeResult>> Function())>[
      ('D1', () async => [await _git1()]),
      ('D2', () async => [await _workTree()]),
      ('D3', () async => [await _hooksDirectory()]),
      ('D4', () => _configuredHooks(config)),
      ('D5', () async => [await _onPath()]),
      ('D6', () async => [await _minVersion()]),
      (
        'D7',
        () async {
          final (result, loaded) = await _configFile();
          config = loaded;
          return [result];
        },
      ),
      ('D8', () async => [await _resolvedSdk(config)]),
      ('D9', _packageConfigs),
      ('D10', () => _customChecks(config)),
    ];
    // D4 needs the config, so the config is loaded first, without a line.
    try {
      config = (await _load()).config;
    } on Object {
      config = null;
    }
    final results = <ProbeResult>[];
    for (final (id, probe) in probes) {
      try {
        results.addAll(await probe());
      } on Object catch (error) {
        final first = error.toString().split('\n').first;
        results.add(ProbeResult(id, ProbeStatus.fail, 'Probe failed: $first'));
      }
    }
    return results;
  }

  Future<LoadedConfig> _load() => _loader.load(
    _git.files(const IndexSnapshot()),
    toolVersion: _toolVersion,
    catalog: _catalog,
  );

  Future<ProbeResult> _git1() async {
    final line = await _probes.gitVersion();
    if (line == null) {
      return const ProbeResult(
        'D1',
        ProbeStatus.fail,
        'git not found on PATH.',
      );
    }
    final words = line.trim().split(' ');
    final version = words.length >= 3 ? words[2] : line.trim();
    final numbers = version
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final major = numbers.isNotEmpty ? numbers[0] : 0;
    final minor = numbers.length > 1 ? numbers[1] : 0;
    final old = major < 2 || (major == 2 && minor < 30);
    return old
        ? ProbeResult(
            'D1',
            ProbeStatus.fail,
            'git $version is older than 2.30.',
          )
        : ProbeResult('D1', ProbeStatus.ok, 'git $version');
  }

  Future<ProbeResult> _workTree() async {
    try {
      final layout = await _git.layout();
      return ProbeResult('D2', ProbeStatus.ok, 'Work tree: ${layout.root}');
    } on UsageException {
      return ProbeResult(
        'D2',
        ProbeStatus.fail,
        'Not inside a git work tree: ${_environment.workingDirectory}.',
      );
    }
  }

  Future<ProbeResult> _hooksDirectory() async {
    final layout = await _git.layout();
    String normalized(String path) => path.replaceAll(r'\', '/');
    final standard = '${normalized(layout.commonDir)}/hooks';
    return normalized(layout.hooksDir) == standard
        ? ProbeResult(
            'D3',
            ProbeStatus.ok,
            'Hooks directory: ${layout.hooksDir}',
          )
        : ProbeResult(
            'D3',
            ProbeStatus.warn,
            'Hooks directory: ${layout.hooksDir} (core.hooksPath is set)',
          );
  }

  Future<List<ProbeResult>> _configuredHooks(Config? config) async => [
    for (final hook in HookName.values)
      if (config == null || config.hooks.containsKey(hook.fileName))
        await _hook(hook),
  ];

  Future<ProbeResult> _hook(HookName hook) async {
    final content = await _hooks.read(hook);
    final name = hook.fileName;
    if (content == null) {
      return ProbeResult(
        'D4',
        ProbeStatus.warn,
        '$name hook is missing. Run: stagelatch install',
      );
    }
    return content.contains('stagelatch:managed')
        ? ProbeResult(
            'D4',
            ProbeStatus.ok,
            '$name hook is managed by stagelatch.',
          )
        : ProbeResult(
            'D4',
            ProbeStatus.warn,
            '$name hook is not managed by stagelatch.',
          );
  }

  Future<ProbeResult> _onPath() async {
    for (final name in const ['stagelatch', 'stagelatch.bat']) {
      final path = await _probes.resolveOnPath(name);
      if (path != null) {
        return ProbeResult('D5', ProbeStatus.ok, 'stagelatch on PATH: $path');
      }
    }
    return await _probes.globallyActivated()
        ? const ProbeResult(
            'D5',
            ProbeStatus.warn,
            'stagelatch is not on PATH; hooks fall back to dart pub global '
                'run.',
          )
        : const ProbeResult(
            'D5',
            ProbeStatus.warn,
            'stagelatch is not installed; hooks skip without blocking.',
          );
  }

  /// D6 reads `min_version` itself, because loading the config fails as a
  /// whole when the tool is too old.
  Future<ProbeResult> _minVersion() async {
    final text =
        await _git.files(const IndexSnapshot()).readText(_configPath) ??
        await _worktree.readText(_configPath);
    Version? required;
    if (text != null) {
      final document = _documents.parseYaml(text, _configPath);
      if (document case DocumentParsed(root: LocatedMap(:final entries))) {
        if (entries['min_version']?.value case LocatedScalar(:final value?)) {
          try {
            required = Version.parse('$value');
          } on FormatException {
            required = null;
          }
        }
      }
    }
    if (required == null) {
      return ProbeResult(
        'D6',
        ProbeStatus.ok,
        'stagelatch $_toolVersion; no min_version.',
      );
    }
    return _toolVersion < required
        ? ProbeResult(
            'D6',
            ProbeStatus.fail,
            'stagelatch $_toolVersion is older than min_version $required.',
          )
        : ProbeResult(
            'D6',
            ProbeStatus.ok,
            'stagelatch $_toolVersion satisfies min_version $required.',
          );
  }

  Future<(ProbeResult, Config?)> _configFile() async {
    final staged =
        await _git.files(const IndexSnapshot()).entry(_configPath) != null;
    final present = staged || await _worktree.readText(_configPath) != null;
    try {
      final loaded = await _load();
      return (
        present
            ? const ProbeResult(
                'D7',
                ProbeStatus.ok,
                'stagelatch.yaml is valid.',
              )
            : const ProbeResult(
                'D7',
                ProbeStatus.ok,
                'No stagelatch.yaml; defaults apply.',
              ),
        loaded.config,
      );
    } on ConfigException catch (error) {
      return (
        ProbeResult('D7', ProbeStatus.fail, 'stagelatch.yaml: $error'),
        null,
      );
    }
  }

  Future<ProbeResult> _resolvedSdk(Config? config) async {
    final effective = config ?? (await _defaults()).config;
    try {
      final sdk = await _sdk.locate(effective);
      final source = switch (sdk.source) {
        SdkSource.sdkPath => 'sdk_path',
        SdkSource.fvm => 'fvm',
        SdkSource.path => 'PATH',
      };
      return ProbeResult(
        'D8',
        ProbeStatus.ok,
        'Dart SDK ${sdk.version} at ${sdk.root} ($source)',
      );
    } on ConfigException catch (error) {
      return ProbeResult('D8', ProbeStatus.fail, error.message);
    }
  }

  /// The configuration of a repository without `stagelatch.yaml`, for D8
  /// when the repository's own config does not load.
  Future<LoadedConfig> _defaults() => ConfigLoader(
    _documents,
    const _EmptyTree(),
  ).load(const _EmptySnapshot(), toolVersion: _toolVersion, catalog: _catalog);

  Future<List<ProbeResult>> _packageConfigs() async {
    final packages = await buildPackageMap(
      _git.files(const IndexSnapshot()),
      _documents,
    );
    final seen = <String>{};
    final results = <ProbeResult>[];
    for (final package in packages.packages) {
      final root = packages.resolutionRootOf(package);
      final key = root?.value ?? '';
      if (!seen.add(key)) continue;
      results.add(await _packageConfig(root));
    }
    return results;
  }

  Future<ProbeResult> _packageConfig(RepoPath? root) async {
    final path = [
      ...?root?.value.split('/'),
      '.dart_tool',
      'package_config.json',
    ].join('/');
    return await _probes.packageConfigExists(root)
        ? ProbeResult('D9', ProbeStatus.ok, '$path found.')
        : ProbeResult(
            'D9',
            ProbeStatus.warn,
            'Missing $path. Run: dart pub get',
          );
  }

  /// One line per configured custom check: id, resolved command, sources,
  /// and whether the executable resolves (docs/specs/custom-checks.md §12).
  /// Never prints environment variable values (S5/S11).
  Future<List<ProbeResult>> _customChecks(Config? config) async {
    final checks = config?.customChecks ?? const [];
    if (checks.isEmpty) return const [];
    ResolvedSdk? sdk;
    try {
      sdk = await _sdk.locate(config ?? (await _defaults()).config);
    } on Object {
      sdk = null;
    }
    return [for (final check in checks) await _customCheck(check, sdk)];
  }

  Future<ProbeResult> _customCheck(
    CustomCheckConfig check,
    ResolvedSdk? sdk,
  ) async {
    final resolved = await _resolveCustomCommand(check.run, sdk);
    final sources = check.sources.map((path) => path.value).join(', ');
    final command = resolved.argv.join(' ');
    final ok = resolved.executableFound;
    return ProbeResult(
      'D10',
      ok ? ProbeStatus.ok : ProbeStatus.warn,
      'custom check "${check.id}": $command '
          '(sources: $sources; '
          '${ok ? 'executable ok' : 'executable not found'})',
    );
  }

  Future<({List<String> argv, bool executableFound})> _resolveCustomCommand(
    List<String> run,
    ResolvedSdk? sdk,
  ) async {
    if (run.isEmpty) {
      return (argv: const <String>[], executableFound: false);
    }
    final head = run.first;
    final rest = run.skip(1).toList();
    if (head == 'dart') {
      final dart = sdk?.dartExecutable;
      return (argv: [dart ?? 'dart', ...rest], executableFound: dart != null);
    }
    if (head == 'flutter') {
      final flutter = sdk?.flutterExecutable;
      return (
        argv: [flutter ?? 'flutter', ...rest],
        executableFound: flutter != null,
      );
    }
    if (head.contains('/') || head.contains(r'\')) {
      return (argv: run, executableFound: true);
    }
    final absolute = await _probes.resolveOnPath(head);
    return (
      argv: [absolute ?? head, ...rest],
      executableFound: absolute != null,
    );
  }
}

/// A snapshot with no files.
final class _EmptySnapshot implements SnapshotFiles {
  const new();

  @override
  Future<SnapshotEntry?> entry(RepoPath path) async => null;

  @override
  Future<List<SnapshotEntry>> list({RepoPath? under}) async => const [];

  @override
  Future<Uint8List?> readBytes(RepoPath path) async => null;

  @override
  Future<String?> readText(RepoPath path) async => null;

  @override
  Future<int?> size(RepoPath path) async => null;
}

/// A working tree with no files.
final class _EmptyTree implements WorkingTree {
  const new();

  @override
  Future<String?> readText(RepoPath path) async => null;

  @override
  Future<void> writeText(RepoPath path, String content) =>
      throw UnsupportedError('The empty working tree is read-only.');

  @override
  Future<bool> exists(RepoPath path) async => false;
}

/// The machine-facing questions of `doctor`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/application/ports/doctor_probes.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/io/path_executable.dart';

/// Answers [DoctorProbes] from the file system and `git --version`.
///
/// It starts only git (security S1) and prints no environment value (S5):
/// variables are read to find directories, never echoed.
final class LocalDoctorProbes implements DoctorProbes {
  /// Creates the probes for the repository at `repoRoot`.
  new({required this._repoRoot, required this._environment});

  final String _repoRoot;
  final Environment _environment;

  static final bool _windows = Platform.isWindows;

  @override
  Future<String?> gitVersion() async {
    final git = _resolveOnPath('git');
    if (git == null) return null;
    try {
      final result = await Process.run(git, const ['--version']);
      if (result.exitCode != 0) return null;
      return (result.stdout as String).split('\n').first.trim();
    } on ProcessException {
      return null;
    }
  }

  @override
  Future<String?> resolveOnPath(String name) async => _resolveOnPath(name);

  /// Absolute PATH hit for [name], skipping repository-controlled entries.
  String? _resolveOnPath(String name) {
    final variables = _environment.variables;
    final pathEnv =
        variables['PATH'] ??
        variables['Path'] ??
        Platform.environment['PATH'] ??
        Platform.environment['Path'] ??
        '';
    return resolvePathExecutable(
      name: name,
      pathEntries: splitPathEnv(pathEnv, isWindows: _windows),
      repoRoot: _repoRoot,
      isWindows: _windows,
      pathExtensions: pathExtSuffixes(
        variables['PATHEXT'] ?? Platform.environment['PATHEXT'],
      ),
    );
  }

  /// `dart pub global activate` records each package under
  /// `<pub cache>/global_packages/<name>`, which is what
  /// `dart pub global list` reads.
  @override
  Future<bool> globallyActivated() async =>
      Directory(p.join(_pubCache(), 'global_packages', 'stagelatch'))
          .existsSync();

  String _pubCache() {
    final variables = _environment.variables;
    final configured = variables['PUB_CACHE'];
    if (configured != null && configured.isNotEmpty) return configured;
    if (_windows) {
      return p.join(variables['LOCALAPPDATA'] ?? '', 'Pub', 'Cache');
    }
    return p.join(variables['HOME'] ?? '', '.pub-cache');
  }

  @override
  Future<bool> packageConfigExists(RepoPath? packageRoot) async => File(
    p.joinAll([
      _repoRoot,
      ...?packageRoot?.value.split('/'),
      '.dart_tool',
      'package_config.json',
    ]),
  ).existsSync();
}

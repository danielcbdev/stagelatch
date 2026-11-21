/// The Dart toolchain of one pipeline phase, created on first use
/// (docs/architecture.md, 5.3.1).
library;

import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/config/settings.dart';
import 'package:stagelatch/src/application/ports/dart_toolchain_factory.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// Stands in for the real toolchain until a check asks it something; only
/// then is the SDK located and the toolchain created. A run whose checks
/// need no Dart knowledge never pays for either.
final class LazyToolchain implements DartToolchain {
  /// Creates the stand-in for `snapshot`.
  new({
    required this._locator,
    required this._factory,
    required this._config,
    required this._repoRoot,
    required this._snapshot,
    required this._packages,
  });

  final SdkLocator _locator;
  final DartToolchainFactory _factory;
  final Config _config;
  final Future<String> Function() _repoRoot;
  final SnapshotFiles _snapshot;
  final PackageMap _packages;

  Future<DartToolchain>? _real;

  /// Shared by concurrent callers, so a phase creates one toolchain.
  Future<DartToolchain> _get() => _real ??= () async {
    final sdk = await _locator.locate(_config);
    return _factory.create(
      sdk: sdk,
      repoRoot: await _repoRoot(),
      snapshot: _snapshot,
      packages: _packages,
      testFunctions: _config.settings<TestsSettings>().functions.toSet(),
    );
  }();

  @override
  Future<List<DartDiagnostic>> diagnose(Set<RepoPath> files) async =>
      await (await _get()).diagnose(files);

  @override
  Future<FormatOutcome> format(RepoPath path, String source) async =>
      await (await _get()).format(path, source);

  @override
  Future<DartFileFacts?> facts(SnapshotFiles files, RepoPath path) async =>
      await (await _get()).facts(files, path);

  /// Closes the real toolchain, if one was created.
  @override
  Future<void> close() async {
    final real = _real;
    if (real == null) return;
    final DartToolchain toolchain;
    try {
      toolchain = await real;
    } on Object {
      // Creation failed: there is nothing to close.
      return;
    }
    await toolchain.close();
  }
}

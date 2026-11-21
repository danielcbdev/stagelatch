/// The test runner of one pipeline run, created on first use (ADR-0018).
library;

import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/application/ports/test_runner_factory.dart';
import 'package:stagelatch/src/domain/dart/test_runner.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// Stands in for the real runner until a check asks it to run tests; only
/// then is the SDK located and the runner created. A run that starts no
/// test never pays for either.
final class LazyTestRunner implements TestRunner {
  /// Creates the stand-in.
  new({
    required this._locator,
    required this._factory,
    required this._config,
    required this._repoRoot,
  });

  final SdkLocator _locator;
  final TestRunnerFactory _factory;
  final Config _config;
  final Future<String> Function() _repoRoot;

  Future<TestRunner>? _real;

  /// Shared by concurrent callers, so a run creates one runner.
  Future<TestRunner> _get() => _real ??= () async {
    final sdk = await _locator.locate(_config);
    return _factory.create(sdk: sdk, repoRoot: await _repoRoot());
  }();

  @override
  Future<TestRunResult> run(DartPackage package, List<RepoPath> files) async =>
      await (await _get()).run(package, files);
}

import 'dart:async';

import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/application/ports/test_runner_factory.dart';
import 'package:stagelatch/src/domain/dart/test_runner.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// One call of [FakeTestRunner.run].
typedef TestRunCall = ({DartPackage package, List<RepoPath> files});

/// A [TestRunner] with canned answers that records every call.
final class FakeTestRunner implements TestRunner {
  /// Creates a runner.
  ///
  /// [results] answer by package name; a package that is not there gets
  /// [fallback]. When [onRun] is set it runs first on each call, so a test
  /// can change the world "while the tests run".
  new({
    this.results = const {},
    this.fallback = const TestRunResult(),
    this.onRun,
  });

  /// The canned result of each package, by name.
  final Map<String, TestRunResult> results;

  /// The result of a package that [results] does not mention.
  final TestRunResult fallback;

  /// Runs at the start of each call, before the result is returned.
  final FutureOr<void> Function(DartPackage package, List<RepoPath> files)?
  onRun;

  /// Every call, in order.
  final List<TestRunCall> calls = [];

  @override
  Future<TestRunResult> run(DartPackage package, List<RepoPath> files) async {
    calls.add((package: package, files: files));
    await onRun?.call(package, files);
    return results[package.name] ?? fallback;
  }
}

/// A [TestRunnerFactory] that hands out one [FakeTestRunner] and records
/// what it was asked for.
final class FakeTestRunnerFactory implements TestRunnerFactory {
  /// Creates a factory that hands out [runner].
  new(this.runner);

  /// The runner every `create` returns.
  final FakeTestRunner runner;

  /// The SDKs `create` was called with, in order.
  final List<ResolvedSdk> sdks = [];

  /// The repository roots `create` was called with, in order.
  final List<String> repoRoots = [];

  /// How many runners were created.
  int get createCount => sdks.length;

  @override
  TestRunner create({required ResolvedSdk sdk, required String repoRoot}) {
    sdks.add(sdk);
    repoRoots.add(repoRoot);
    return runner;
  }
}

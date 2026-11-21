/// Explains why `tests/affected` selects a test (docs/specs/cli.md, 3.8).
library;

import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/packages/import_graph_builder.dart';
import 'package:stagelatch/src/application/packages/package_map_builder.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/lazy_toolchain.dart';
import 'package:stagelatch/src/application/ports/dart_toolchain_factory.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/checks/tests/affected_tests.dart';
import 'package:stagelatch/src/checks/tests/test_key.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// How a chain reaches the test.
enum WhyOrigin {
  /// A changed `.dart` file the test depends on.
  changed,

  /// A deleted `.dart` file, or the old path of a rename.
  deleted,

  /// A changed `pubspec.yaml`, `analysis_options.yaml` or `pubspec.lock`.
  configuration,
}

/// One reason the test is affected.
@immutable
final class WhyChain {
  /// Creates a chain. [files] starts at the changed path; for an import
  /// chain it ends at the test. For [WhyOrigin.configuration] it holds
  /// only the changed path and [package] is the package it configures.
  const new({required this.origin, required this.files, this.package});

  /// What kind of change starts the chain.
  final WhyOrigin origin;

  /// The changed path first; the test last when [origin] is not
  /// [WhyOrigin.configuration].
  final List<RepoPath> files;

  /// The package a configuration change selects every test of.
  final DartPackage? package;
}

/// The explanation for one test file.
@immutable
final class WhyResult {
  /// Creates the result.
  const new({required this.test, required this.chains});

  /// The test that was asked about.
  final RepoPath test;

  /// One chain per changed file that reaches [test], in path order.
  final List<WhyChain> chains;
}

/// Builds [WhyResult] for a test against the index.
final class Why {
  /// Creates the use case.
  new({
    required this._git,
    required this._configLoader,
    required this._registry,
    required this._documents,
    required this._sdkLocator,
    required this._toolchains,
    required this._toolVersion,
  });

  final GitRepository _git;
  final ConfigLoader _configLoader;
  final CheckRegistry _registry;
  final Documents _documents;
  final SdkLocator _sdkLocator;
  final DartToolchainFactory _toolchains;
  final Version _toolVersion;

  /// Why [testFile] is (or is not) selected for the index against [baseRef].
  ///
  /// Throws [UsageException] when [testFile] is not a test file of a
  /// package of the index, or is absent from the index.
  Future<WhyResult> explain(RepoPath testFile, {String? baseRef}) async {
    final run = await _git.resolveAgainstIndex(baseRef: baseRef);
    final snapshot = _git.files(run.snapshot);
    final loaded = await _configLoader.load(
      snapshot,
      toolVersion: _toolVersion,
      catalog: _registry,
    );
    final packages = await buildPackageMap(snapshot, _documents);
    final snapshotPaths = {
      for (final entry in await snapshot.list()) entry.path,
    };
    if (!snapshotPaths.contains(testFile) || !isTestFile(testFile, packages)) {
      throw UsageException('$testFile is not a test file of any package.');
    }

    final testPackage = packages.packageOf(testFile)!;
    final toolchain = LazyToolchain(
      locator: _sdkLocator,
      factory: _toolchains,
      config: loaded.config,
      repoRoot: () async => (await _git.layout()).root,
      snapshot: snapshot,
      packages: packages,
    );
    try {
      final graph = await buildImportGraph(
        dart: toolchain,
        snapshot: snapshot,
        packages: packages,
      );
      final selection = selectAffectedTests(
        graph: graph,
        changes: run.changes,
        packages: packages,
        snapshotPaths: snapshotPaths,
      );
      final deleted = _deletedPaths(run.changes);
      final chains = <WhyChain>[
        for (final source in selection.sources)
          if (graph.shortestChain(source, testFile) case final chain?)
            WhyChain(
              origin: deleted.contains(source)
                  ? WhyOrigin.deleted
                  : WhyOrigin.changed,
              files: chain,
            ),
        for (final MapEntry(:key, :value) in selection.widenedBy.entries)
          if (value.contains(testPackage))
            WhyChain(
              origin: WhyOrigin.configuration,
              files: [key],
              package: testPackage,
            ),
      ]..sort((a, b) => a.files.first.compareTo(b.files.first));
      return WhyResult(test: testFile, chains: List.unmodifiable(chains));
    } finally {
      await toolchain.close();
    }
  }
}

/// The console rendering of [result] (docs/specs/cli.md, section 3.8).
String renderWhy(WhyResult result) {
  if (result.chains.isEmpty) {
    return '${result.test} is not affected by the current changes.\n';
  }
  final buffer = StringBuffer()
    ..writeln(
      '${result.test} is affected by '
      '${_changedFiles(result.chains.length)}:',
    )
    ..writeln();
  for (var i = 0; i < result.chains.length; i++) {
    final chain = result.chains[i];
    final root = chain.files.first;
    final label = chain.origin == WhyOrigin.deleted ? 'deleted' : 'changed';
    buffer.writeln('${root.value} ($label)');
    if (chain.origin == WhyOrigin.configuration) {
      final at = chain.package!.root?.value ?? '.';
      buffer.writeln('  configures every test of the package at $at');
    } else {
      for (final step in chain.files.skip(1)) {
        buffer.writeln('  imported by ${step.value}');
      }
    }
    if (i + 1 < result.chains.length) buffer.writeln();
  }
  return buffer.toString();
}

String _changedFiles(int count) =>
    count == 1 ? '1 changed file' : '$count changed files';

Set<RepoPath> _deletedPaths(ChangeSet changes) {
  final deleted = <RepoPath>{};
  for (final change in changes.changes) {
    if (change.kind == ChangeKind.deleted) deleted.add(change.path);
    final previous = change.previousPath;
    if (previous != null) deleted.add(previous);
  }
  return deleted;
}

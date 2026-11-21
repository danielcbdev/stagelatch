/// Which tests a changeset affects (ADR-0018, `tests/affected`).
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/checks/tests/test_key.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/dart/import_graph.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// The tests a changeset affects, and what they read.
@immutable
final class AffectedTests {
  /// Creates a selection. [selectAffectedTests] is the way to get one.
  const new({
    required this.testFiles,
    required this.byPackage,
    required this.sources,
    required this.widenedBy,
    required this.closure,
  });

  /// The selected test files, sorted by path. Every one exists in the
  /// snapshot.
  final List<RepoPath> testFiles;

  /// [testFiles] grouped by the package that owns them, ordered by package
  /// root with the repository root first; the files of each are sorted.
  final Map<DartPackage, List<RepoPath>> byPackage;

  /// The `.dart` paths whose dependents were walked: changed, deleted and
  /// previous paths. Sorted.
  final Set<RepoPath> sources;

  /// A changed `pubspec.yaml`, `analysis_options.yaml` or committed
  /// `pubspec.lock` and the packages whose every test it selected. Sorted
  /// by path.
  final Map<RepoPath, List<DartPackage>> widenedBy;

  /// What running [testFiles] reads: their forward import closure (targets
  /// absent from the snapshot included) and, for each package that owns a
  /// selected test, its `pubspec.yaml`, its `analysis_options.yaml` (both
  /// whether or not they exist) and its `pubspec.lock` when it is in the
  /// snapshot. Sorted.
  final Set<RepoPath> closure;
}

/// Selects the tests of the snapshot that [changes] can affect.
///
/// A test is affected when it depends, through `import`, `export` or
/// `part`, on a `.dart` file that was changed, deleted or renamed (the old
/// path of a rename counts, so a test that still imports it is found). A
/// changed `pubspec.yaml` or `analysis_options.yaml`, and a changed
/// `pubspec.lock` still in the snapshot, affect every test of the package
/// that owns it. A deleted lock selects nothing.
///
/// [snapshotPaths] is every path of the snapshot. Pure: no I/O.
AffectedTests selectAffectedTests({
  required ImportGraph graph,
  required ChangeSet changes,
  required PackageMap packages,
  required Set<RepoPath> snapshotPaths,
}) {
  final sources = <RepoPath>{};
  final gone = <RepoPath>{};
  for (final change in changes.changes) {
    if (change.kind == ChangeKind.deleted) {
      gone.add(change.path);
    } else if (change.path.extension == '.dart') {
      sources.add(change.path);
    }
    final previous = change.previousPath;
    if (previous != null) gone.add(previous);
  }
  sources.addAll(gone.where((path) => path.extension == '.dart'));

  bool selectable(RepoPath path) =>
      snapshotPaths.contains(path) &&
      !gone.contains(path) &&
      isTestFile(path, packages);

  final selected = <RepoPath>{
    for (final path in graph.dependentsOf(sources))
      if (selectable(path)) path,
  };

  final widened = <RepoPath, List<DartPackage>>{};
  final testsOfPackage = <DartPackage, List<RepoPath>>{};
  List<RepoPath> testsOf(DartPackage package) => testsOfPackage[package] ??= [
    for (final path in snapshotPaths)
      if (selectable(path) && packages.packageOf(path) == package) path,
  ];

  void widen(RepoPath path, {required bool wholeWorkspace}) {
    final package = packages.packageOf(path);
    if (package == null) return;
    final targets = wholeWorkspace
        ? packages.workspaceMembersOf(package)
        : [package];
    widened[path] = targets;
    for (final target in targets) {
      selected.addAll(testsOf(target));
    }
  }

  for (final change in changes.changes) {
    final deleted = change.kind == ChangeKind.deleted;
    for (final path in [change.path, ?change.previousPath]) {
      switch (path.basename) {
        case 'pubspec.yaml':
          final package = packages.packageOf(path);
          final atResolutionRoot =
              package != null &&
              packages.resolutionPackageOf(package) == package;
          widen(path, wholeWorkspace: atResolutionRoot);
        case 'analysis_options.yaml':
          widen(path, wholeWorkspace: false);
        case 'pubspec.lock' when !deleted && path == change.path:
          widen(path, wholeWorkspace: true);
      }
    }
  }

  final testFiles = [...selected]..sort();

  final grouped = <DartPackage, List<RepoPath>>{};
  for (final package in packages.packages) {
    final own = [
      for (final path in testFiles)
        if (packages.packageOf(path) == package) path,
    ];
    if (own.isNotEmpty) grouped[package] = own;
  }

  final closure = <RepoPath>{...graph.dependenciesOf(testFiles.toSet())};
  for (final package in grouped.keys) {
    final root = package.root;
    RepoPath inPackage(String name) =>
        RepoPath(root == null ? name : '${root.value}/$name');
    closure
      ..add(inPackage('pubspec.yaml'))
      ..add(inPackage('analysis_options.yaml'));
    final resolution = packages.resolutionPackageOf(package);
    if (resolution != package) {
      final resolutionRoot = resolution.root;
      closure.add(
        RepoPath(
          resolutionRoot == null
              ? 'pubspec.yaml'
              : '${resolutionRoot.value}/pubspec.yaml',
        ),
      );
    }
    final lockRoot = packages.resolutionRootOf(package);
    final lock = RepoPath(
      lockRoot == null ? 'pubspec.lock' : '${lockRoot.value}/pubspec.lock',
    );
    if (snapshotPaths.contains(lock)) closure.add(lock);
  }

  return AffectedTests(
    testFiles: List.unmodifiable(testFiles),
    byPackage: Map.unmodifiable(grouped),
    sources: Set.unmodifiable([...sources]..sort()),
    widenedBy: Map.unmodifiable(
      Map.fromEntries(
        widened.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    ),
    closure: Set.unmodifiable([...closure]..sort()),
  );
}

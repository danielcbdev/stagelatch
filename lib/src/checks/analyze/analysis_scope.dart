/// Which files `analyze` asks the toolchain about (docs/specs/rules.md,
/// `analyze`).
library;

import 'package:stagelatch/src/checks/analyze/analyze_settings.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

const Set<String> _widening = {'pubspec.yaml', 'analysis_options.yaml'};

/// Whether [changes] hold anything `analyze` reacts to: a `.dart` file, a
/// `pubspec.yaml` or an `analysis_options.yaml`, present or deleted.
bool triggersAnalysis(ChangeSet changes) => changes.changes.any(
  (change) => [change.path, ?change.previousPath].any(
    (path) => path.extension == '.dart' || _widening.contains(path.basename),
  ),
);

/// The Dart files of the snapshot to analyze for [scope], sorted.
///
/// A package whose `pubspec.yaml` or `analysis_options.yaml` changed is
/// analyzed whole. Deleted files are never requested; under `affected`
/// their importers are. Only regular files that belong to a package count.
Future<Set<RepoPath>> analysisScope(
  CheckContext context,
  AnalyzeScope scope,
) async {
  final changedDart = <RepoPath>{};
  final deletedDart = <RepoPath>{};
  final widened = <DartPackage>{};
  for (final change in context.changes.changes) {
    final previous = change.previousPath;
    if (change.kind == ChangeKind.deleted) {
      if (change.path.extension == '.dart') deletedDart.add(change.path);
    } else if (change.path.extension == '.dart') {
      changedDart.add(change.path);
    }
    if (previous != null && previous.extension == '.dart') {
      deletedDart.add(previous);
    }
    for (final path in [change.path, ?previous]) {
      if (!_widening.contains(path.basename)) continue;
      final package = context.packages.packageOf(path);
      if (package != null) widened.add(package);
    }
  }

  final files = <RepoPath>{...changedDart};
  if (scope == AnalyzeScope.affected) {
    final graph = await context.importGraph;
    files.addAll(graph.dependentsOf({...changedDart, ...deletedDart}));
  }
  if (scope == AnalyzeScope.all) {
    for (final path in [...changedDart, ...deletedDart]) {
      final package = context.packages.packageOf(path);
      if (package != null) widened.add(package);
    }
  }
  if (widened.isNotEmpty) {
    for (final entry in await context.snapshot.list()) {
      if (entry.path.extension != '.dart') continue;
      if (widened.contains(context.packages.packageOf(entry.path))) {
        files.add(entry.path);
      }
    }
  }

  final result = <RepoPath>[];
  for (final path in files) {
    if (path.extension != '.dart') continue;
    if (context.packages.packageOf(path) == null) continue;
    final entry = await context.snapshot.entry(path);
    if (entry == null || !entry.mode.isFile) continue;
    result.add(path);
  }
  return {...result..sort()};
}

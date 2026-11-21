/// `tests/affected`: runs the tests a change can affect, only when the
/// working tree is what is being published (ADR-0018,
/// docs/specs/rules.md).
library;

import 'package:stagelatch/src/checks/tests/affected_tests.dart';
import 'package:stagelatch/src/checks/tests/tests_rules.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/dart/import_graph.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The findings of `tests/affected` for [context].
///
/// Nothing is reported, asked or started on `pre-commit`, when the rule is
/// not enabled, when the change touches no `.dart`, `pubspec.yaml`,
/// `pubspec.lock` or `analysis_options.yaml` file, or when no test is
/// affected.
///
/// Otherwise the tests run only if [CheckContext.divergentAmong] finds
/// nothing in the closure of the selection, before the first process and
/// again after the last one. A divergent closure is one `warning`, never
/// an error: a skip is not a failure of the code, and `ci` is the guarantee
/// (ADR-0018). Its severity cannot be raised through `rules:`.
Future<List<Finding>> affectedFindings(CheckContext context) async {
  if (context.entry == EntryKind.preCommit) return const [];
  if (!context.isEnabled(affectedRule)) return const [];
  if (!context.changes.changes.any(_concernsTests)) return const [];

  final graph = await context.importGraph;
  final snapshotPaths = {
    for (final entry in await context.snapshot.list()) entry.path,
  };
  final selection = selectAffectedTests(
    graph: graph,
    changes: context.changes,
    packages: context.packages,
    snapshotPaths: snapshotPaths,
  );
  if (selection.testFiles.isEmpty) return const [];

  final before = await context.divergentAmong(selection.closure);
  if (before.isNotEmpty) {
    return [_skipped(before, selection, graph, snapshotPaths)];
  }

  final results = [
    for (final MapEntry(key: package, value: files)
        in selection.byPackage.entries)
      (files: files, result: await context.tests.run(package, files)),
  ];

  // An edit made while the tests ran, or a tracked file they wrote into the
  // closure: the verdict would be about code that was never validated.
  final after = await context.divergentAmong(selection.closure);
  if (after.isNotEmpty) {
    return [_skipped(after, selection, graph, snapshotPaths)];
  }

  return [
    for (final (:files, :result) in results) ...[
      for (final failure in result.failures)
        Finding(
          rule: affectedRule,
          severity: Severity.error,
          message: 'Test failed: ${failure.name}.',
          location: Location(
            failure.file,
            Position(failure.line, failure.column),
            Position(failure.line, failure.column),
          ),
        ),
      if (result.startupError case final error?)
        Finding(
          rule: affectedRule,
          severity: Severity.error,
          message: 'Tests could not be run: $error.',
          location: Location.wholeFile(files.first),
        ),
    ],
  ];
}

/// Whether [change] can alter which tests pass, or the packages they run in.
bool _concernsTests(FileChange change) =>
    _concerns(change.path) ||
    (change.previousPath != null && _concerns(change.previousPath!));

bool _concerns(RepoPath path) =>
    path.extension == '.dart' ||
    switch (path.basename) {
      'pubspec.yaml' || 'pubspec.lock' || 'analysis_options.yaml' => true,
      _ => false,
    };

/// The one warning that stands for a skipped run.
Finding _skipped(
  Set<RepoPath> divergent,
  AffectedTests selection,
  ImportGraph graph,
  Set<RepoPath> snapshotPaths,
) {
  final first = ([...divergent]..sort()).first;
  var location = Location.wholeFile(first);
  if (!snapshotPaths.contains(first)) {
    // An untracked import target: point at the directive that names it, in
    // the first file of the closure, in path order, that imports it.
    for (final importer in selection.closure) {
      final directive = graph.directiveOf(importer, first);
      if (directive != null) {
        location = directive;
        break;
      }
    }
  }
  return Finding(
    rule: affectedRule,
    severity: Severity.warning,
    severityLocked: true,
    message:
        'Affected tests were not run: ${divergent.length} file(s) they '
        'execute differ from the working tree (uncommitted changes, '
        'untracked files, or another checked-out commit).',
    location: location,
  );
}

import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// A [Documents] that returns canned results by path.
///
/// Used until the real parser exists (plan 01, task 7); after that, tests
/// that need parsed YAML use the real adapter over a fake snapshot.
final class FakeDocuments implements Documents {
  /// Creates the fake. A path without a canned result is reported missing.
  const new(this._results);

  final Map<String, DocumentResult> _results;

  @override
  Future<DocumentResult> yaml(SnapshotFiles files, RepoPath path) async =>
      _results[path.value] ?? const DocumentMissing();

  @override
  Future<DocumentResult> json(SnapshotFiles files, RepoPath path) async =>
      _results[path.value] ?? const DocumentMissing();

  @override
  DocumentResult parseYaml(String text, RepoPath path) =>
      _results[path.value] ?? const DocumentMissing();
}

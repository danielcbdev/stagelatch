import 'package:stagelatch/src/application/ports/working_tree.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// An in-memory [WorkingTree].
final class FakeWorkingTree implements WorkingTree {
  /// Creates a working tree holding [files], keyed by path.
  new([Map<String, String> files = const {}]) : files = {...files};

  /// The current content of the tree. Tests may read and change it.
  final Map<String, String> files;

  @override
  Future<String?> readText(RepoPath path) async => files[path.value];

  @override
  Future<void> writeText(RepoPath path, String content) async {
    files[path.value] = content;
  }

  @override
  Future<bool> exists(RepoPath path) async => files.containsKey(path.value);
}

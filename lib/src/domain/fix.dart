/// Automatic corrections a check can propose.
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';

/// The full replacement text for one file of the snapshot.
///
/// A fix is whole-file on purpose: it is written to the index as one blob
/// (ADR-0002), so there is no partial edit to get wrong.
@immutable
final class Fix {
  /// Creates a fix that replaces [path] with [content] on behalf of [rule].
  const new({required this.rule, required this.path, required this.content});

  /// The rule whose finding this fix resolves.
  final RuleId rule;

  /// The file to replace.
  final RepoPath path;

  /// The new text of the whole file, with the line endings to store.
  final String content;

  @override
  bool operator ==(Object other) =>
      other is Fix &&
      other.rule == rule &&
      other.path == path &&
      other.content == content;

  @override
  int get hashCode => Object.hash(rule, path, content);

  @override
  String toString() => 'Fix($rule, $path)';
}

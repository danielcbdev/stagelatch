/// Structured documents (YAML and JSON) with source locations.
library;

import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// The outcome of reading a structured document from a snapshot.
sealed class DocumentResult {
  const new();
}

/// The snapshot has no file at the requested path.
final class DocumentMissing extends DocumentResult {
  /// Creates the result.
  const new();
}

/// The file exists but could not be parsed.
///
/// A check turns this into a finding such as `pubspec/unparseable`; it is
/// never an exception, because broken user content is not a tool failure.
final class DocumentInvalid extends DocumentResult {
  /// Creates the result.
  const new({required this.location, required this.reason});

  /// Where parsing failed, or the first character when unknown.
  final Location location;

  /// The parser's explanation, as one sentence fragment without a period.
  final String reason;
}

/// The file was parsed.
final class DocumentParsed extends DocumentResult {
  /// Creates the result.
  const new(this.root);

  /// The top-level node of the document.
  final LocatedNode root;
}

/// A node of a parsed document that knows where it came from.
///
/// Checks walk these instead of a parser's own tree, so that they do not
/// depend on a parsing library and can report exact locations.
sealed class LocatedNode {
  const new({required this.location});

  /// The range the node occupies in its file.
  final Location location;
}

/// A mapping with string keys, in document order.
final class LocatedMap extends LocatedNode {
  /// Creates a map node.
  const new({required super.location, required this.entries});

  /// The entries by key. Iteration follows document order.
  final Map<String, LocatedEntry> entries;
}

/// A sequence.
final class LocatedList extends LocatedNode {
  /// Creates a list node.
  const new({required super.location, required this.items});

  /// The elements, in document order.
  final List<LocatedNode> items;
}

/// A scalar: a string, number, boolean or null.
final class LocatedScalar extends LocatedNode {
  /// Creates a scalar node.
  const new({required super.location, required this.value});

  /// The parsed value: `String`, `num`, `bool` or null.
  final Object? value;
}

/// One entry of a [LocatedMap].
final class LocatedEntry {
  /// Creates an entry.
  const new({required this.keyLocation, required this.value});

  /// Where the key is written. Rules that flag a whole section point here.
  final Location keyLocation;

  /// The value of the entry.
  final LocatedNode value;
}

/// Reads YAML and JSON files of a snapshot into [LocatedNode] trees.
abstract interface class Documents {
  /// Parses the file at [path] of [files] as YAML.
  Future<DocumentResult> yaml(SnapshotFiles files, RepoPath path);

  /// Parses the file at [path] of [files] as strict JSON.
  Future<DocumentResult> json(SnapshotFiles files, RepoPath path);

  /// Parses [text] as YAML, as if it were the content of [path].
  ///
  /// For text that does not come from a snapshot, such as a configuration
  /// file that exists only in the working tree. Never returns
  /// [DocumentMissing].
  DocumentResult parseYaml(String text, RepoPath path);
}

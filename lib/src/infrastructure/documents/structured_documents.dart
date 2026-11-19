/// YAML and JSON files of a snapshot, parsed with source locations.
library;

import 'dart:convert';

import 'package:source_span/source_span.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:yaml/yaml.dart';

/// The most nodes a document may have after aliases are expanded.
///
/// YAML aliases let a few kilobytes of text describe billions of nodes.
/// Repository content is untrusted (security rule S6), and no manifest or
/// translation file a rule reads comes near this size.
const int maxDocumentNodes = 100000;

/// The deepest nesting of `[` and `{` a document may have.
///
/// The YAML library's cost grows with the square of flow nesting depth:
/// 100 KB of `[` take half a minute, and more exhausts the stack. Real
/// manifests and translation files nest a handful of levels.
const int maxFlowNesting = 256;

const String _nestedTooDeeply = 'the document is nested too deeply';

/// Whether [text] opens more than [limit] brackets or braces without
/// closing them, in one linear pass.
///
/// Quoting is deliberately not interpreted, so brackets inside strings
/// count too. That can only reject a file whose strings hold hundreds of
/// unbalanced brackets, which is an acceptable price for a guard that
/// cannot itself be fooled or made slow (security rule S6).
bool _flowNestingExceeds(String text, int limit) {
  var depth = 0;
  for (var index = 0; index < text.length; index++) {
    switch (text.codeUnitAt(index)) {
      case 0x5B || 0x7B: // [ or {
        if (++depth > limit) return true;
      case 0x5D || 0x7D: // ] or }
        if (depth > 0) depth--;
    }
  }
  return false;
}

/// [Documents] backed by `package:yaml`.
///
/// It reads content only through [SnapshotFiles], so it parses exactly
/// what is in the snapshot. A file that cannot be parsed is reported as
/// [DocumentInvalid], never thrown: broken user content is a finding, not
/// a failure of the tool.
final class StructuredDocuments implements Documents {
  /// Creates the reader.
  const new();

  @override
  Future<DocumentResult> yaml(SnapshotFiles files, RepoPath path) async {
    final text = await _read(files, path);
    return text.result ?? _parse(text.content, path);
  }

  @override
  DocumentResult parseYaml(String text, RepoPath path) =>
      _flowNestingExceeds(text, maxFlowNesting)
      ? DocumentInvalid(
          location: Location.wholeFile(path),
          reason: _nestedTooDeeply,
        )
      : _parse(text, path);

  @override
  Future<DocumentResult> json(SnapshotFiles files, RepoPath path) async {
    final text = await _read(files, path);
    if (text.result case final failure?) return failure;
    try {
      // JSON is validated by the JSON decoder, which is strict. Locations
      // then come from the YAML parser, since every JSON document is also
      // a YAML document.
      jsonDecode(text.content);
    } on FormatException catch (error) {
      return DocumentInvalid(
        location: _atOffset(path, text.content, error.offset ?? 0),
        reason: _reason(error.message),
      );
    }
    return _parse(text.content, path);
  }

  /// Reads [path] as text, or says why there is nothing to parse.
  Future<({String content, DocumentResult? result})> _read(
    SnapshotFiles files,
    RepoPath path,
  ) async {
    if (await files.entry(path) == null) {
      return (content: '', result: const DocumentMissing());
    }
    final text = await files.readText(path);
    if (text == null) {
      return (
        content: '',
        result: DocumentInvalid(
          location: Location.wholeFile(path),
          reason: 'the file is not readable text',
        ),
      );
    }
    if (_flowNestingExceeds(text, maxFlowNesting)) {
      return (
        content: '',
        result: DocumentInvalid(
          location: Location.wholeFile(path),
          reason: _nestedTooDeeply,
        ),
      );
    }
    return (content: text, result: null);
  }

  DocumentResult _parse(String text, RepoPath path) {
    try {
      final root = loadYamlNode(text);
      return DocumentParsed(_Converter(path).convert(root));
    } on YamlException catch (error) {
      return DocumentInvalid(
        location: _fromSpan(path, error.span),
        reason: _reason(error.message),
      );
    } on _Rejected catch (rejected) {
      return DocumentInvalid(
        location: rejected.location,
        reason: rejected.reason,
      );
      // The YAML loader and the conversion below are recursive, and nesting
      // depth is controlled by the file's author. Flow nesting is bounded
      // before parsing; this is the backstop for the other ways YAML can
      // nest (compact sequences, indentation), where only the overflow
      // itself tells. So this one Error is caught on purpose and reported
      // as invalid content (security rule S6).
      // ignore: avoid_catching_errors, see the comment above
    } on StackOverflowError {
      return DocumentInvalid(
        location: Location.wholeFile(path),
        reason: _nestedTooDeeply,
      );
    }
  }
}

/// Turns the YAML library's tree into [LocatedNode]s, counting nodes.
final class _Converter {
  new(this._path);

  final RepoPath _path;
  int _nodes = 0;

  LocatedNode convert(YamlNode node) {
    final location = _fromSpan(_path, node.span);
    // Aliases are shared in the library's tree but expanded here, so the
    // count is what bounds an alias bomb.
    if (++_nodes > maxDocumentNodes) {
      throw _Rejected(location, 'the document is too large');
    }
    return switch (node) {
      YamlMap() => LocatedMap(
        location: location,
        entries: Map.unmodifiable({
          for (final MapEntry(:key, :value) in node.nodes.entries)
            _keyName(key): LocatedEntry(
              keyLocation: _keyLocation(key),
              value: convert(value),
            ),
        }),
      ),
      YamlList() => LocatedList(
        location: location,
        items: List.unmodifiable([
          for (final item in node.nodes) convert(item),
        ]),
      ),
      _ => LocatedScalar(location: location, value: node.value),
    };
  }

  /// The key of a mapping entry, which must be a string scalar. YAML also
  /// allows numbers, lists and maps as keys; no file we read uses them.
  String _keyName(Object? key) {
    if (key case YamlScalar(value: final String name)) return name;
    throw _Rejected(_keyLocation(key), 'map keys must be strings');
  }

  Location _keyLocation(Object? key) =>
      _fromSpan(_path, key is YamlNode ? key.span : null);
}

/// Content that parses but that this tool refuses to accept.
final class _Rejected implements Exception {
  const new(this.location, this.reason);

  final Location location;
  final String reason;
}

/// Converts a 0-based source span into a 1-based [Location]; without a
/// span, points at the first character of the file.
Location _fromSpan(RepoPath path, SourceSpan? span) {
  if (span == null) return Location.wholeFile(path);
  return Location(
    path,
    Position(span.start.line + 1, span.start.column + 1),
    Position(span.end.line + 1, span.end.column + 1),
  );
}

/// The location of the character at [offset] in [text].
Location _atOffset(RepoPath path, String text, int offset) {
  final end = offset.clamp(0, text.length);
  var line = 1;
  var lineStart = 0;
  for (var index = 0; index < end; index++) {
    if (text.codeUnitAt(index) == 0x0A) {
      line++;
      lineStart = index + 1;
    }
  }
  final position = Position(line, end - lineStart + 1);
  return Location(path, position, position);
}

/// A parser message as a sentence fragment: one line, no final period, so
/// that it can be placed inside the tool's own sentence.
String _reason(String message) {
  final firstLine = const LineSplitter().convert(message.trim()).firstOrNull;
  final text = (firstLine ?? '').trim();
  return text.endsWith('.') ? text.substring(0, text.length - 1) : text;
}

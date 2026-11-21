/// The fingerprint that identifies a finding in the baseline
/// (docs/specs/baseline-and-suppression.md section 4.2).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// Normalizes the lines of a snippet.
///
/// Each line is trimmed, runs of spaces and tabs inside a line collapse to
/// one space, and the lines are joined with one space. Formatting changes
/// therefore never invalidate a baseline entry.
String normalizeSnippet(List<String> lines) =>
    [for (final line in lines) line.trim().replaceAll(_blankRun, ' ')]
        .join(' ');

final RegExp _blankRun = RegExp('[ \t]+');

/// The SHA-256 hex digest of `rule`, `path` and the normalized snippet of
/// [finding], separated by line feeds.
///
/// The snippet is the text of [snapshot] from the finding's start line to
/// its end line, inclusive. It is empty when the file is absent, is not
/// text, or does not reach those lines. The line number itself is not part
/// of the digest, so inserting lines above a finding keeps its entry valid.
Future<String> fingerprintOf(Finding finding, SnapshotFiles snapshot) async {
  final location = finding.location;
  final text = await snapshot.readText(location.path);
  final lines = text == null
      ? const <String>[]
      : const LineSplitter().convert(text);
  final first = location.start.line - 1;
  final last = location.end.line < lines.length
      ? location.end.line
      : lines.length;
  final snippet = first >= lines.length
      ? const <String>[]
      : lines.sublist(first < 0 ? 0 : first, last);
  final input =
      '${finding.rule}\n${location.path.value}\n${normalizeSnippet(snippet)}';
  return sha256.convert(utf8.encode(input)).toString();
}

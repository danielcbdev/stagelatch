/// Reading and writing the baseline file
/// (docs/specs/baseline-and-suppression.md section 4.1).
library;

import 'dart:convert';

import 'package:stagelatch/src/application/baseline/baseline.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';

/// The only format version there is.
const int baselineVersion = 1;

final RegExp _fingerprint = RegExp(r'^[0-9a-f]{64}$');

/// Parses the text of a baseline file.
///
/// Throws a [ConfigException] for text that is not JSON, for an unknown
/// `version`, and for a malformed or repeated entry. When [path] is given
/// the exception points at that file.
Baseline decodeBaseline(String json, {RepoPath? path}) {
  Never fail(String problem) => throw ConfigException(
    'Invalid baseline: $problem',
    location: path == null ? null : Location.wholeFile(path),
  );

  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException catch (error) {
    fail('not valid JSON (${error.message}).');
  }
  if (root is! Map<String, Object?>) fail('expected a JSON object.');
  if (root['version'] != baselineVersion) {
    fail('unsupported version ${jsonEncode(root['version'])}; expected 1.');
  }
  final entries = root['entries'];
  if (entries is! List<Object?>) fail('"entries" must be a list.');

  final seen = <(RuleId, RepoPath, String)>{};
  final decoded = <BaselineEntry>[];
  for (final (index, raw) in entries.indexed) {
    if (raw is! Map<String, Object?>) fail('entry $index is not an object.');
    final rule = raw['rule'];
    final file = raw['path'];
    final fingerprint = raw['fingerprint'];
    final count = raw['count'];
    if (rule is! String || file is! String) {
      fail('entry $index needs a string "rule" and a string "path".');
    }
    if (fingerprint is! String || !_fingerprint.hasMatch(fingerprint)) {
      fail('entry $index needs a "fingerprint" of 64 hexadecimal digits.');
    }
    if (count is! int || count < 1) {
      fail('entry $index needs a positive integer "count".');
    }
    final BaselineEntry entry;
    try {
      entry = BaselineEntry(
        rule: RuleId.parse(rule),
        path: RepoPath(file),
        fingerprint: fingerprint,
        count: count,
      );
    } on FormatException catch (error) {
      fail('entry $index: ${error.message}');
    }
    if (!seen.add((entry.rule, entry.path, entry.fingerprint))) {
      fail('entry $index repeats an earlier entry.');
    }
    decoded.add(entry);
  }
  return Baseline(List.unmodifiable(decoded));
}

/// The text of [baseline]: two-space indentation, a trailing newline and
/// entries sorted by path, rule and fingerprint, so that diffs stay small.
String encodeBaseline(Baseline baseline) {
  final sorted = [...baseline.entries]..sort(BaselineEntry.compare);
  final document = {
    'version': baselineVersion,
    'entries': [
      for (final entry in sorted)
        {
          'rule': entry.rule.toString(),
          'path': entry.path.value,
          'fingerprint': entry.fingerprint,
          'count': entry.count,
        },
    ],
  };
  return '${const JsonEncoder.withIndent('  ').convert(document)}\n';
}

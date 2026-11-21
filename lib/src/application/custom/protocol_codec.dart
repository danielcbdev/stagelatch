/// Encode and decode custom-check protocol lines
/// (docs/specs/custom-checks.md sections 10–11).
library;

import 'dart:convert';

import 'package:stagelatch/src/application/custom/protocol.dart';
import 'package:stagelatch/src/application/text/sanitize.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Maximum UTF-8 size of one stdout line from the child (custom-checks.md §11).
///
/// A longer line is a protocol error; the host must not keep parsing it.
const int maxProtocolLineBytes = 1 << 20; // 1 MiB

/// How many characters of an offending line appear in [ProtocolException.line]
/// after S5 sanitization (custom-checks.md §11).
const int _maxOffendingLineChars = 200;

/// A line from the child that is not a valid protocol message.
final class ProtocolException implements Exception {
  /// Creates the failure. [reason] is the short clause after
  /// `protocol error:`; [line] is the sanitized, truncated offending text.
  const new(this.reason, {this.line});

  /// Why the line was rejected.
  final String reason;

  /// Offending line after [sanitizeForTerminal], truncated to 200 characters.
  final String? line;

  @override
  String toString() => line == null
      ? 'ProtocolException: $reason'
      : 'ProtocolException: $reason ($line)';
}

/// One JSON object for [message], UTF-8, no pretty-print and no trailing
/// newline. The process host appends the line terminator when sending.
String encodeToCheck(ToCheck message) => switch (message) {
  InitMessage(
    :final protocol,
    :final entry,
    :final settings,
    :final capabilities,
  ) =>
    jsonEncode({
      'type': 'init',
      'protocol': protocol,
      'entry': _encodeEntry(entry),
      'settings': settings,
      'capabilities': capabilities,
    }),
  RunMessage(:final changes, :final all) => jsonEncode({
    'type': 'run',
    'changes': [for (final change in changes) _encodeChange(change)],
    'all': all,
  }),
  ContentMessage(:final id, :final text) => jsonEncode({
    'type': 'content',
    'id': id,
    'text': text,
  }),
};

/// Parses one stdout [line] from the child into a [FromCheck] message.
///
/// Throws [ProtocolException] for a line over [maxProtocolLineBytes], for
/// non-JSON, for an unknown `type`, for a missing or mistyped field, and for
/// a `ready` whose `protocol` is not [customCheckProtocol].
FromCheck decodeFromCheck(String line) {
  if (utf8.encode(line).length > maxProtocolLineBytes) {
    throw ProtocolException('line exceeds 1 MiB', line: _offendingLine(line));
  }

  final Object? json;
  try {
    json = jsonDecode(line);
  } on FormatException {
    throw ProtocolException('not valid JSON', line: _offendingLine(line));
  }

  return switch (json) {
    final Map<String, Object?> map => _decodeMap(map, line),
    _ => throw ProtocolException(
      'expected a JSON object',
      line: _offendingLine(line),
    ),
  };
}

FromCheck _decodeMap(Map<String, Object?> map, String line) {
  Never fail(String reason) =>
      throw ProtocolException(reason, line: _offendingLine(line));

  return switch (map) {
    {'type': 'ready'} => _decodeReady(map, fail),
    {
      'type': 'read',
      'id': final Object? id,
      'path': final Object? path,
      'side': final Object? side,
    } =>
      _decodeRead(id, path, side, fail),
    {'type': 'read'} => fail(_firstMissing(map, const ['id', 'path', 'side'])),
    {
      'type': 'finding',
      'rule': final Object? rule,
      'path': final Object? path,
      'line': final Object? findingLine,
      'column': final Object? column,
      'message': final Object? message,
    } =>
      _decodeFinding(rule, path, findingLine, column, message, fail),
    {'type': 'finding'} => fail(
      _firstMissing(map, const ['rule', 'path', 'line', 'column', 'message']),
    ),
    {'type': 'done'} => const DoneMessage(),
    {'type': final String type} => fail('unknown type "$type"'),
    final map when map.containsKey('type') => fail('"type" must be a string'),
    _ => fail('missing "type"'),
  };
}

/// First key in [required] that is absent from [map], as `missing "<key>"`.
String _firstMissing(Map<String, Object?> map, List<String> required) {
  for (final key in required) {
    if (!map.containsKey(key)) return 'missing "$key"';
  }
  // Every required key is present but a more specific pattern did not match
  // (for example a null that still counts as present). Surface the first key.
  return 'missing "${required.first}"';
}

ReadyMessage _decodeReady(
  Map<String, Object?> map,
  Never Function(String reason) fail,
) {
  if (!map.containsKey('protocol')) fail('missing "protocol"');
  if (!map.containsKey('rules')) fail('missing "rules"');
  final protocol = map['protocol'];
  final rules = map['rules'];
  if (protocol is! int) fail('"protocol" must be an integer');
  if (protocol != customCheckProtocol) {
    fail('unsupported protocol $protocol; expected $customCheckProtocol');
  }
  if (rules is! List<Object?>) fail('"rules" must be a list');
  final decoded = <RuleDescriptor>[];
  for (final (index, raw) in rules.indexed) {
    decoded.add(_decodeRule(raw, index, fail));
  }
  return ReadyMessage(protocol: protocol, rules: decoded);
}

RuleDescriptor _decodeRule(
  Object? raw,
  int index,
  Never Function(String reason) fail,
) {
  return switch (raw) {
    {
      'id': final Object? id,
      'summary': final Object? summary,
      'defaultSeverity': final Object? severity,
    } =>
      _ruleDescriptor(id, summary, severity, index, fail),
    {'id': final Object? id, 'summary': final Object? summary} =>
      _ruleDescriptor(id, summary, null, index, fail),
    final Map<String, Object?> rule when rule.containsKey('id') => fail(
      'rules[$index] missing "summary"',
    ),
    Map<String, Object?>() => fail('rules[$index] missing "id"'),
    _ => fail('rules[$index] must be an object'),
  };
}

RuleDescriptor _ruleDescriptor(
  Object? id,
  Object? summary,
  Object? severity,
  int index,
  Never Function(String reason) fail,
) {
  if (id is! String) fail('"rules[$index].id" must be a string');
  if (summary is! String) fail('"rules[$index].summary" must be a string');
  final RuleId ruleId;
  try {
    ruleId = RuleId.parse(id);
  } on FormatException {
    fail('invalid rule "$id"');
  }
  final defaultSeverity = switch (severity) {
    null => Severity.error,
    'error' => Severity.error,
    'warning' => Severity.warning,
    _ => fail('"rules[$index].defaultSeverity" must be "error" or "warning"'),
  };
  return RuleDescriptor(
    id: ruleId,
    defaultSeverity: defaultSeverity,
    summary: summary,
  );
}

ReadMessage _decodeRead(
  Object? id,
  Object? path,
  Object? side,
  Never Function(String reason) fail,
) {
  if (id is! int) fail('"id" must be an integer');
  if (path is! String) fail('"path" must be a string');
  if (side is! String) fail('"side" must be a string');
  if (side != 'snapshot' && side != 'base') {
    fail('side must be "snapshot" or "base"');
  }
  final RepoPath repoPath;
  try {
    repoPath = RepoPath(path);
  } on FormatException {
    fail('invalid path "$path"');
  }
  return ReadMessage(id: id, path: repoPath, side: side);
}

FindingMessage _decodeFinding(
  Object? rule,
  Object? path,
  Object? line,
  Object? column,
  Object? message,
  Never Function(String reason) fail,
) {
  if (rule is! String) fail('"rule" must be a string');
  if (path is! String) fail('"path" must be a string');
  if (line is! int) fail('"line" must be an integer');
  if (column is! int) fail('"column" must be an integer');
  if (message is! String) fail('"message" must be a string');
  if (line < 1) fail('"line" must be >= 1');
  if (column < 1) fail('"column" must be >= 1');
  final RuleId ruleId;
  try {
    ruleId = RuleId.parse(rule);
  } on FormatException {
    fail('invalid rule "$rule"');
  }
  final RepoPath repoPath;
  try {
    repoPath = RepoPath(path);
  } on FormatException {
    fail('invalid path "$path"');
  }
  return FindingMessage(
    rule: ruleId,
    path: repoPath,
    line: line,
    column: column,
    message: message,
  );
}

String _encodeEntry(EntryKind entry) => switch (entry) {
  EntryKind.preCommit => 'pre-commit',
  EntryKind.prePush => 'pre-push',
  EntryKind.ci => 'ci',
};

Map<String, Object?> _encodeChange(FileChange change) => switch (change.kind) {
  ChangeKind.added || ChangeKind.modified || ChangeKind.deleted => {
    'path': change.path.value,
    'kind': change.kind.name,
    'previousPath': null,
  },
  ChangeKind.renamed => {
    'path': change.path.value,
    'kind': 'renamed',
    'previousPath': change.previousPath?.value,
  },
  ChangeKind.typeChanged => throw ArgumentError.value(
    change.kind,
    'kind',
    'custom-check protocol 1 has no wire form for typeChanged',
  ),
};

String _offendingLine(String line) {
  final sanitized = sanitizeForTerminal(line);
  return sanitized.length <= _maxOffendingLineChars
      ? sanitized
      : sanitized.substring(0, _maxOffendingLineChars);
}

/// Wire messages for the custom-check protocol
/// (docs/specs/custom-checks.md section 10).
library;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';

/// Protocol version spoken by stagelatch 1.0.0 (`protocol: 1`).
const int customCheckProtocol = 1;

/// A message the host sends to a custom-check child.
sealed class ToCheck {
  const new();
}

/// Handshake: entry point, settings and negotiated capabilities.
@immutable
final class InitMessage implements ToCheck {
  /// Creates an init message.
  ///
  /// [capabilities] is always empty in protocol 1.
  const new({
    required this.protocol,
    required this.entry,
    required this.settings,
    this.capabilities = const [],
  });

  /// Wire protocol version. Must be [customCheckProtocol] for 1.0.0.
  final int protocol;

  /// Which entry point started the run.
  final EntryKind entry;

  /// Extra keys from `custom_checks.<id>` excluding reserved ones.
  final Map<String, Object?> settings;

  /// Capability names the host offers. Empty in protocol 1.
  final List<String> capabilities;

  @override
  bool operator ==(Object other) =>
      other is InitMessage &&
      other.protocol == protocol &&
      other.entry == entry &&
      const DeepCollectionEquality().equals(other.settings, settings) &&
      const ListEquality<String>().equals(other.capabilities, capabilities);

  @override
  int get hashCode => Object.hash(
    protocol,
    entry,
    const DeepCollectionEquality().hash(settings),
    const ListEquality<String>().hash(capabilities),
  );
}

/// Starts the check over [changes], or the whole snapshot when [all] is true.
@immutable
final class RunMessage implements ToCheck {
  /// Creates a run message. [changes] is stored unmodifiable.
  new({required List<FileChange> changes, required this.all})
    : changes = List.unmodifiable(changes);

  /// Paths that differ between base and snapshot.
  final List<FileChange> changes;

  /// Whether `--all` was passed.
  final bool all;

  @override
  bool operator ==(Object other) =>
      other is RunMessage &&
      const ListEquality<FileChange>().equals(other.changes, changes) &&
      other.all == all;

  @override
  int get hashCode =>
      Object.hash(const ListEquality<FileChange>().hash(changes), all);
}

/// Answer to a child's [ReadMessage].
@immutable
final class ContentMessage implements ToCheck {
  /// Creates a content answer. [text] is null when the path is missing,
  /// unreadable, binary, or over the text size limit.
  const new({required this.id, this.text});

  /// Correlation id from the matching [ReadMessage].
  final int id;

  /// File text, or null when it cannot be served.
  final String? text;

  @override
  bool operator ==(Object other) =>
      other is ContentMessage && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

/// A message a custom-check child sends to the host.
sealed class FromCheck {
  const new();
}

/// Handshake reply: protocol version and the rules this check declares.
@immutable
final class ReadyMessage implements FromCheck {
  /// Creates a ready message. [rules] is stored unmodifiable.
  new({required this.protocol, required List<RuleDescriptor> rules})
    : rules = List.unmodifiable(rules);

  /// Wire protocol version the child speaks.
  final int protocol;

  /// Rules the child may emit findings for.
  final List<RuleDescriptor> rules;

  @override
  bool operator ==(Object other) =>
      other is ReadyMessage &&
      other.protocol == protocol &&
      _ruleDescriptorsEqual(other.rules, rules);

  @override
  int get hashCode =>
      Object.hash(protocol, Object.hashAll(rules.map(_ruleHash)));
}

/// Requests file text from the snapshot or the changeset base.
@immutable
final class ReadMessage implements FromCheck {
  /// Creates a read request. [side] is `snapshot` or `base`.
  const new({required this.id, required this.path, required this.side});

  /// Correlation id for the matching [ContentMessage].
  final int id;

  /// Repository-relative path to read.
  final RepoPath path;

  /// `snapshot` or `base`.
  final String side;

  @override
  bool operator ==(Object other) =>
      other is ReadMessage &&
      other.id == id &&
      other.path == path &&
      other.side == side;

  @override
  int get hashCode => Object.hash(id, path, side);
}

/// One finding from the child.
@immutable
final class FindingMessage implements FromCheck {
  /// Creates a finding. [line] and [column] are 1-based.
  const new({
    required this.rule,
    required this.path,
    required this.line,
    required this.column,
    required this.message,
  });

  /// Rule id, `<check>/<rule>`.
  final RuleId rule;

  /// Path the finding points at.
  final RepoPath path;

  /// 1-based line.
  final int line;

  /// 1-based column.
  final int column;

  /// Human-readable description.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is FindingMessage &&
      other.rule == rule &&
      other.path == path &&
      other.line == line &&
      other.column == column &&
      other.message == message;

  @override
  int get hashCode => Object.hash(rule, path, line, column, message);
}

/// Ends the child's turn successfully.
@immutable
final class DoneMessage implements FromCheck {
  /// Creates a done message.
  const new();

  @override
  bool operator ==(Object other) => other is DoneMessage;

  @override
  int get hashCode => 0;
}

bool _ruleDescriptorsEqual(List<RuleDescriptor> a, List<RuleDescriptor> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final left = a[i];
    final right = b[i];
    if (left.id != right.id ||
        left.defaultSeverity != right.defaultSeverity ||
        left.summary != right.summary ||
        left.fixable != right.fixable) {
      return false;
    }
  }
  return true;
}

int _ruleHash(RuleDescriptor rule) =>
    Object.hash(rule.id, rule.defaultSeverity, rule.summary, rule.fixable);

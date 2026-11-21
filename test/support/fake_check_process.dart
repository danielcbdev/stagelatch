import 'dart:async';
import 'dart:convert';

import 'package:stagelatch/src/application/custom/protocol.dart';
import 'package:stagelatch/src/application/ports/check_process.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// A scripted [CheckProcess] for unit-testing ExternalCheck.
///
/// Decodes each host line, calls [onMessage], and emits the returned
/// replies. [hangsUntilKilled] never closes [lines] or completes [exitCode]
/// until [kill].
final class FakeCheckProcess implements CheckProcess {
  /// Creates a fake child.
  new({
    this.onMessage = defaultWellBehaved,
    this.exitCodeValue = 0,
    this.hangsUntilKilled = false,
    this.standardErrorValue = '',
    this.failStart = false,
  }) {
    if (!hangsUntilKilled) {
      _stderr.complete(standardErrorValue);
    }
  }

  /// Replies for one decoded host message.
  final FutureOr<List<FromCheck>> Function(
    ToCheck message,
    FakeCheckProcess process,
  )
  onMessage;

  /// Exit code once the scripted turn ends (or after [kill]).
  final int exitCodeValue;

  /// Whether the child stays alive until [kill].
  final bool hangsUntilKilled;

  /// Stderr text exposed after the child ends.
  final String standardErrorValue;

  /// When true, [FakeCheckProcessFactory.start] throws before returning.
  final bool failStart;

  final _lines = StreamController<String>();
  final _exit = Completer<int>();
  final _stderr = Completer<String>();

  /// Host lines received, in order.
  final List<String> received = [];

  var _stdinClosed = false;
  var _killed = false;

  /// Whether the factory marked this instance as started.
  bool started = false;

  /// Whether [kill] was called.
  bool get killed => _killed;

  /// Whether [closeStdin] was called.
  bool get stdinClosed => _stdinClosed;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  void send(String line) {
    if (_stdinClosed) {
      throw StateError('stdin is closed');
    }
    received.add(line);
    unawaited(_handle(line));
  }

  Future<void> _handle(String line) async {
    final message = decodeToCheck(line);
    final replies = await onMessage(message, this);
    for (final reply in replies) {
      if (_lines.isClosed) return;
      _lines.add(encodeFromCheck(reply));
    }
    if (!hangsUntilKilled && message is RunMessage) {
      await _finish(exitCodeValue);
    }
  }

  /// Emits a raw stdout line (for noisy-child tests).
  void emitRaw(String line) {
    if (!_lines.isClosed) _lines.add(line);
  }

  Future<void> _finish(int code) async {
    if (!_lines.isClosed) await _lines.close();
    if (!_stderr.isCompleted) _stderr.complete(standardErrorValue);
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Future<void> closeStdin() async {
    _stdinClosed = true;
  }

  @override
  Future<void> kill() async {
    _killed = true;
    await _finish(hangsUntilKilled ? -15 : exitCodeValue);
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Future<String> get standardError => _stderr.future;

  /// Default script: ready with `team/no-print`, then done on run.
  static FutureOr<List<FromCheck>> defaultWellBehaved(
    ToCheck message,
    FakeCheckProcess process,
  ) => switch (message) {
    InitMessage() => [
      ReadyMessage(
        protocol: customCheckProtocol,
        rules: [
          RuleDescriptor(
            id: RuleId.parse('team/no-print'),
            defaultSeverity: Severity.error,
            summary: 'No print calls',
          ),
        ],
      ),
    ],
    RunMessage() => [const DoneMessage()],
    ContentMessage() => const [],
  };
}

/// Encodes a child→host message the same way a real peer would.
String encodeFromCheck(FromCheck message) => switch (message) {
  ReadyMessage(:final protocol, :final rules) => jsonEncode({
    'type': 'ready',
    'protocol': protocol,
    'rules': [
      for (final rule in rules)
        {
          'id': rule.id.toString(),
          'summary': rule.summary,
          'defaultSeverity': rule.defaultSeverity.name,
        },
    ],
  }),
  ReadMessage(:final id, :final path, :final side) => jsonEncode({
    'type': 'read',
    'id': id,
    'path': path.value,
    'side': side,
  }),
  FindingMessage(
    :final rule,
    :final path,
    :final line,
    :final column,
    :final message,
  ) =>
    jsonEncode({
      'type': 'finding',
      'rule': rule.toString(),
      'path': path.value,
      'line': line,
      'column': column,
      'message': message,
    }),
  DoneMessage() => jsonEncode({'type': 'done'}),
};

/// Decodes a host→child line produced by `encodeToCheck`.
ToCheck decodeToCheck(String line) {
  final json = jsonDecode(line);
  if (json is! Map<String, Object?>) {
    throw FormatException('expected a JSON object', line);
  }
  return switch (json) {
    {
      'type': 'init',
      'protocol': final int protocol,
      'entry': final String entry,
      'settings': final Map<String, Object?> settings,
      'capabilities': final List<Object?> capabilities,
    } =>
      InitMessage(
        protocol: protocol,
        entry: switch (entry) {
          'pre-commit' => EntryKind.preCommit,
          'pre-push' => EntryKind.prePush,
          'ci' => EntryKind.ci,
          _ => throw FormatException('unknown entry "$entry"', line),
        },
        settings: settings,
        capabilities: [for (final c in capabilities) '$c'],
      ),
    {
      'type': 'run',
      'changes': final List<Object?> changes,
      'all': final bool all,
    } =>
      RunMessage(
        changes: [
          for (final raw in changes)
            if (raw is Map<String, Object?>) _change(raw),
        ],
        all: all,
      ),
    {'type': 'content', 'id': final int id, 'text': final Object? text} =>
      ContentMessage(id: id, text: text as String?),
    _ => throw FormatException('unknown host message', line),
  };
}

FileChange _change(Map<String, Object?> raw) {
  final path = RepoPath(raw['path']! as String);
  final kindName = raw['kind'];
  if (kindName is! String) {
    throw FormatException('unknown kind', kindName);
  }
  final kind = switch (kindName) {
    'added' => ChangeKind.added,
    'modified' => ChangeKind.modified,
    'deleted' => ChangeKind.deleted,
    'renamed' => ChangeKind.renamed,
    _ => throw FormatException('unknown kind', raw['kind']),
  };
  final previous = raw['previousPath'];
  return FileChange(
    path: path,
    kind: kind,
    previousPath: previous is String ? RepoPath(previous) : null,
  );
}

/// A [CheckProcessFactory] that hands out scripted processes.
final class FakeCheckProcessFactory implements CheckProcessFactory {
  /// Creates a factory. [create] builds each child; defaults to one
  /// well-behaved [FakeCheckProcess] per start.
  new({FakeCheckProcess Function()? create})
    : _create = create ?? FakeCheckProcess.new;

  final FakeCheckProcess Function() _create;

  /// Every [start] call: command and working directory.
  final List<(List<String> command, String workingDirectory)> starts = [];

  /// The last process returned, if any.
  FakeCheckProcess? last;

  @override
  Future<CheckProcess> start(
    List<String> command, {
    required String workingDirectory,
  }) async {
    starts.add((List.unmodifiable(command), workingDirectory));
    final process = _create()..started = true;
    last = process;
    if (process.failStart) {
      throw StateError('cannot start');
    }
    return process;
  }
}

/// Builds a well-behaved responder for [checkId] with optional findings
/// and read requests after [RunMessage].
FutureOr<List<FromCheck>> Function(ToCheck, FakeCheckProcess)
wellBehavedScript({
  String checkId = 'team',
  String rule = 'no-print',
  String summary = 'No print calls',
  Severity severity = Severity.error,
  List<FindingMessage> findings = const [],
  List<ReadMessage> reads = const [],
  List<String> rawAfterInit = const [],
}) {
  final ruleId = RuleId(checkId, rule);
  return (message, process) async {
    switch (message) {
      case InitMessage():
        rawAfterInit.forEach(process.emitRaw);
        return [
          ReadyMessage(
            protocol: customCheckProtocol,
            rules: [
              RuleDescriptor(
                id: ruleId,
                defaultSeverity: severity,
                summary: summary,
              ),
            ],
          ),
        ];
      case RunMessage():
        return [...reads, ...findings, const DoneMessage()];
      case ContentMessage():
        return const [];
    }
  };
}

/// A finding for tests.
FindingMessage finding({
  String rule = 'team/no-print',
  String path = 'lib/a.dart',
  int line = 1,
  int column = 1,
  String message = 'print found',
}) => FindingMessage(
  rule: RuleId.parse(rule),
  path: RepoPath(path),
  line: line,
  column: column,
  message: message,
);

/// A read request for tests.
ReadMessage readRequest({
  int id = 1,
  String path = 'lib/a.dart',
  String side = 'snapshot',
}) => ReadMessage(id: id, path: RepoPath(path), side: side);

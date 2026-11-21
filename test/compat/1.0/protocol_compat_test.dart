import 'dart:convert';

import 'package:stagelatch/src/application/custom/protocol.dart';
import 'package:stagelatch/src/application/custom/protocol_codec.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import 'fixtures_path.dart';

ToCheck _toCheck(Map<String, Object?> obj) {
  switch (obj['type']) {
    case 'init':
      return InitMessage(
        protocol: obj['protocol']! as int,
        entry: switch (obj['entry']! as String) {
          'pre-commit' => EntryKind.preCommit,
          'pre-push' => EntryKind.prePush,
          'ci' => EntryKind.ci,
          final other => throw StateError('unknown entry $other'),
        },
        settings: Map<String, Object?>.from(obj['settings']! as Map),
        capabilities: (obj['capabilities']! as List<Object?>).cast<String>(),
      );
    case 'run':
      return RunMessage(
        all: obj['all']! as bool,
        changes: [
          for (final raw in obj['changes']! as List<Object?>)
            FileChange(
              path: RepoPath((raw! as Map)['path'] as String),
              kind: ChangeKind.values.byName((raw as Map)['kind'] as String),
            ),
        ],
      );
    case 'content':
      return ContentMessage(
        id: obj['id']! as int,
        text: obj['text'] as String?,
      );
    default:
      throw StateError('unknown to-check type ${obj['type']}');
  }
}

void main() {
  test('frozen protocol 1 transcript round-trips through the codec', () {
    final lines = readCompatFixture('protocol_transcript.jsonl')
        .trimRight()
        .split('\n');

    for (final line in lines) {
      final entry = jsonDecode(line) as Map<String, Object?>;
      final dir = entry['dir']! as String;
      final obj = Map<String, Object?>.from(entry['obj']! as Map);

      if (dir == 'to') {
        final encoded = encodeToCheck(_toCheck(obj));
        expect(jsonDecode(encoded), obj);
      } else if (dir == 'from') {
        final message = decodeFromCheck(jsonEncode(obj));
        expect(message, isA<FromCheck>());
        switch (message) {
          case ReadyMessage(:final protocol, :final rules):
            expect(protocol, customCheckProtocol);
            expect(rules.single.id, RuleId.parse('team/no-print'));
            expect(rules.single.defaultSeverity, Severity.error);
          case ReadMessage(:final id, :final path, :final side):
            expect(id, 1);
            expect(path, RepoPath('lib/a.dart'));
            expect(side, 'snapshot');
          case FindingMessage(:final rule, :final path, :final message):
            expect(rule, RuleId.parse('team/no-print'));
            expect(path, RepoPath('lib/a.dart'));
            expect(message, 'Do not call print.');
          case DoneMessage():
            break;
        }
      } else {
        fail('unknown dir $dir');
      }
    }
  });

  test('protocol error behaviour rejects non-protocol stdout', () {
    expect(
      () => decodeFromCheck('not-a-protocol-line'),
      throwsA(isA<ProtocolException>()),
    );
  });
}

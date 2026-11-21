import 'dart:convert';

import 'package:stagelatch/src/application/custom/protocol.dart';
import 'package:stagelatch/src/application/custom/protocol_codec.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

Matcher _protocolError(String reason) => throwsA(
  isA<ProtocolException>()
      .having((error) => error.reason, 'reason', reason)
      .having((error) => error.line, 'line', isNotNull),
);

void main() {
  group('encodeToCheck', () {
    test('round-trips init', () {
      const message = InitMessage(
        protocol: customCheckProtocol,
        entry: EntryKind.prePush,
        settings: {
          'strict': true,
          'paths': <Object?>['lib'],
        },
      );

      final encoded = encodeToCheck(message);
      expect(jsonDecode(encoded), {
        'type': 'init',
        'protocol': 1,
        'entry': 'pre-push',
        'settings': {
          'strict': true,
          'paths': <Object?>['lib'],
        },
        'capabilities': <Object?>[],
      });
      expect(encoded, isNot(contains('\n')));
    });

    test('encodes every entry kind', () {
      expect(
        jsonDecode(
          encodeToCheck(
            const InitMessage(
              protocol: customCheckProtocol,
              entry: EntryKind.preCommit,
              settings: {},
            ),
          ),
        ),
        containsPair('entry', 'pre-commit'),
      );
      expect(
        jsonDecode(
          encodeToCheck(
            const InitMessage(
              protocol: customCheckProtocol,
              entry: EntryKind.ci,
              settings: {},
            ),
          ),
        ),
        containsPair('entry', 'ci'),
      );
    });

    test('round-trips run with every change kind', () {
      final message = RunMessage(
        changes: [
          FileChange(path: RepoPath('lib/a.dart'), kind: ChangeKind.added),
          FileChange(path: RepoPath('lib/b.dart'), kind: ChangeKind.modified),
          FileChange(path: RepoPath('lib/c.dart'), kind: ChangeKind.deleted),
          FileChange(
            path: RepoPath('lib/d.dart'),
            kind: ChangeKind.renamed,
            previousPath: RepoPath('lib/old.dart'),
          ),
        ],
        all: true,
      );

      expect(jsonDecode(encodeToCheck(message)), {
        'type': 'run',
        'changes': [
          {'path': 'lib/a.dart', 'kind': 'added', 'previousPath': null},
          {'path': 'lib/b.dart', 'kind': 'modified', 'previousPath': null},
          {'path': 'lib/c.dart', 'kind': 'deleted', 'previousPath': null},
          {
            'path': 'lib/d.dart',
            'kind': 'renamed',
            'previousPath': 'lib/old.dart',
          },
        ],
        'all': true,
      });
    });

    test('round-trips content with text and with null', () {
      expect(
        jsonDecode(encodeToCheck(const ContentMessage(id: 7, text: 'hi'))),
        {'type': 'content', 'id': 7, 'text': 'hi'},
      );
      expect(jsonDecode(encodeToCheck(const ContentMessage(id: 8))), {
        'type': 'content',
        'id': 8,
        'text': null,
      });
    });
  });

  group('decodeFromCheck', () {
    test('round-trips ready', () {
      final line = jsonEncode({
        'type': 'ready',
        'protocol': 1,
        'rules': [
          {
            'id': 'team/no-print',
            'summary': 'Bans print.',
            'defaultSeverity': 'warning',
          },
          {'id': 'team/no-todo', 'summary': 'Bans TODO.'},
        ],
        'ignored': true,
      });

      expect(
        decodeFromCheck(line),
        ReadyMessage(
          protocol: 1,
          rules: const [
            RuleDescriptor(
              id: RuleId('team', 'no-print'),
              defaultSeverity: Severity.warning,
              summary: 'Bans print.',
            ),
            RuleDescriptor(
              id: RuleId('team', 'no-todo'),
              defaultSeverity: Severity.error,
              summary: 'Bans TODO.',
            ),
          ],
        ),
      );
    });

    test('accepts a rule id whose check segment differs from the check id', () {
      // Host mapping rejects a mismatched check segment; the codec only
      // requires a structurally valid <check>/<rule> id (custom-checks.md §11).
      final message = decodeFromCheck(
        jsonEncode({
          'type': 'ready',
          'protocol': 1,
          'rules': [
            {'id': 'other/no-print', 'summary': 'From another check id.'},
          ],
        }),
      );

      expect(
        message,
        isA<ReadyMessage>().having(
          (m) => m.rules.single.id.toString(),
          'rule id',
          'other/no-print',
        ),
      );
    });

    test('round-trips read for both sides', () {
      expect(
        decodeFromCheck(
          jsonEncode({
            'type': 'read',
            'id': 3,
            'path': 'lib/a.dart',
            'side': 'snapshot',
          }),
        ),
        ReadMessage(id: 3, path: RepoPath('lib/a.dart'), side: 'snapshot'),
      );
      expect(
        decodeFromCheck(
          jsonEncode({
            'type': 'read',
            'id': 4,
            'path': 'lib/a.dart',
            'side': 'base',
          }),
        ),
        ReadMessage(id: 4, path: RepoPath('lib/a.dart'), side: 'base'),
      );
    });

    test('round-trips finding', () {
      expect(
        decodeFromCheck(
          jsonEncode({
            'type': 'finding',
            'rule': 'team/no-print',
            'path': 'lib/a.dart',
            'line': 2,
            'column': 5,
            'message': 'Do not call print.',
            'extra': 'ignored',
          }),
        ),
        FindingMessage(
          rule: RuleId.parse('team/no-print'),
          path: RepoPath('lib/a.dart'),
          line: 2,
          column: 5,
          message: 'Do not call print.',
        ),
      );
    });

    test('round-trips done', () {
      expect(decodeFromCheck('{"type":"done"}'), const DoneMessage());
      expect(decodeFromCheck('{"type":"done","extra":1}'), const DoneMessage());
    });

    test('rejects an unknown type', () {
      expect(
        () => decodeFromCheck('{"type":"init","protocol":1}'),
        _protocolError('unknown type "init"'),
      );
    });

    test('rejects a missing field', () {
      expect(
        () => decodeFromCheck('{"type":"ready","protocol":1}'),
        _protocolError('missing "rules"'),
      );
    });

    test('rejects a wrong field type', () {
      expect(
        () => decodeFromCheck(
          '{"type":"finding","rule":"team/x","path":"lib/a.dart",'
          '"line":"2","column":1,"message":"x"}',
        ),
        _protocolError('"line" must be an integer'),
      );
    });

    test('rejects non-JSON', () {
      expect(
        () => decodeFromCheck('not-json'),
        _protocolError('not valid JSON'),
      );
    });

    test('rejects a line over the size limit', () {
      final oversized = '{"type":"done","pad":"${'x' * maxProtocolLineBytes}"}';
      expect(utf8.encode(oversized).length, greaterThan(maxProtocolLineBytes));
      expect(
        () => decodeFromCheck(oversized),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.reason,
            'reason',
            'line exceeds 1 MiB',
          ),
        ),
      );
    });

    test('rejects a protocol version mismatch', () {
      expect(
        () => decodeFromCheck(
          jsonEncode({'type': 'ready', 'protocol': 2, 'rules': <Object?>[]}),
        ),
        _protocolError('unsupported protocol 2; expected 1'),
      );
    });

    test('sanitizes and truncates the offending line to 200 characters', () {
      final noisy = 'not-json\u0007${'a' * 250}';
      try {
        decodeFromCheck(noisy);
        fail('expected ProtocolException');
      } on ProtocolException catch (error) {
        expect(error.line, isNot(contains('\u0007')));
        expect(error.line, hasLength(200));
        expect(error.line, startsWith('not-json'));
      }
    });

    test('rejects an invalid repository path', () {
      expect(
        () => decodeFromCheck(
          jsonEncode({
            'type': 'read',
            'id': 1,
            'path': '../secret',
            'side': 'snapshot',
          }),
        ),
        _protocolError('invalid path "../secret"'),
      );
    });

    test('rejects an invalid read side', () {
      expect(
        () => decodeFromCheck(
          jsonEncode({
            'type': 'read',
            'id': 1,
            'path': 'lib/a.dart',
            'side': 'working-tree',
          }),
        ),
        _protocolError('side must be "snapshot" or "base"'),
      );
    });

    test('rejects an invalid rule id', () {
      expect(
        () => decodeFromCheck(
          jsonEncode({
            'type': 'finding',
            'rule': 'not-a-rule',
            'path': 'lib/a.dart',
            'line': 1,
            'column': 1,
            'message': 'x',
          }),
        ),
        _protocolError('invalid rule "not-a-rule"'),
      );
    });
  });

  group('message equality', () {
    test('value types compare by fields', () {
      expect(
        const InitMessage(protocol: 1, entry: EntryKind.ci, settings: {'a': 1}),
        const InitMessage(protocol: 1, entry: EntryKind.ci, settings: {'a': 1}),
      );
      expect(
        const ContentMessage(id: 1, text: 'x'),
        const ContentMessage(id: 1, text: 'x'),
      );
      expect(const DoneMessage(), const DoneMessage());
      expect(
        ReadMessage(id: 1, path: RepoPath('a.dart'), side: 'base'),
        ReadMessage(id: 1, path: RepoPath('a.dart'), side: 'base'),
      );
    });
  });
}

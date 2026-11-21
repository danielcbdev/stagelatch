import 'dart:convert';

import 'package:stagelatch/src/application/custom/external_check.dart';
import 'package:stagelatch/src/application/custom/protocol.dart';
import 'package:stagelatch/src/application/custom/protocol_codec.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_check_process.dart';
import '../../support/fake_snapshot_files.dart';

RepoPath path(String value) => RepoPath(value);

ExternalCheck check({
  FakeCheckProcessFactory? factory,
  String id = 'team',
  List<String> command = const ['dart', 'tool/check.dart'],
  Duration timeout = const Duration(seconds: 60),
  Set<RepoPath>? sources,
  Map<String, Object?> settings = const {},
  bool all = false,
  String workingDirectory = '/repo',
}) => ExternalCheck(
  id: id,
  command: command,
  factory: factory ?? FakeCheckProcessFactory(),
  timeout: timeout,
  sourceClosure: sources ?? {path('tool/check.dart')},
  settings: settings,
  all: all,
  workingDirectory: workingDirectory,
);

FakeCheckContext context({
  EntryKind entry = EntryKind.prePush,
  Map<String, Object> files = const {'tool/check.dart': 'void main() {}'},
  Map<String, Object>? baseFiles,
  List<FileChange> changes = const [],
  Set<String> dirty = const {},
  List<Set<String>>? divergentAnswers,
}) => FakeCheckContext(
  entry: entry,
  changes: ChangeSet(changes),
  snapshot: FakeSnapshotFiles(files),
  base: baseFiles == null ? null : FakeSnapshotFiles(baseFiles),
  dirty: {for (final value in dirty) path(value)},
  divergentAnswers: [
    for (final answer in divergentAnswers ?? const <Set<String>>[])
      {for (final value in answer) path(value)},
  ],
);

void main() {
  group('ExternalCheck metadata', () {
    test('is verify-phase with dynamic rules', () {
      final sut = check();
      expect(sut.id, 'team');
      expect(sut.phase, CheckPhase.verify);
      expect(sut.hasDynamicRules, isTrue);
      expect(sut.rules, isEmpty);
    });

    test('rejects an empty sourceClosure at construction', () {
      expect(
        () => ExternalCheck(
          id: 'team',
          command: const ['dart', 'tool/check.dart'],
          factory: FakeCheckProcessFactory(),
          timeout: const Duration(seconds: 60),
          sourceClosure: {},
          workingDirectory: '/repo',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('must be non-empty'),
          ),
        ),
      );
    });
  });

  group('handshake and findings', () {
    test('sends init then run, maps findings from declared rules', () async {
      final factory = FakeCheckProcessFactory(
        create: () => FakeCheckProcess(
          onMessage: wellBehavedScript(findings: [finding()]),
        ),
      );
      final sut = check(factory: factory, settings: const {'strict': true});

      final result = await sut.run(
        context(
          changes: [
            FileChange(path: path('lib/a.dart'), kind: ChangeKind.modified),
            FileChange(path: path('bin/x'), kind: ChangeKind.typeChanged),
          ],
        ),
      );

      expect(factory.starts, hasLength(1));
      expect(factory.starts.single.$1, ['dart', 'tool/check.dart']);
      expect(factory.starts.single.$2, '/repo');

      final process = factory.last!;
      expect(process.received, hasLength(2));
      final init = jsonDecode(process.received[0]) as Map<String, Object?>;
      expect(init['type'], 'init');
      expect(init['protocol'], 1);
      expect(init['entry'], 'pre-push');
      expect(init['settings'], {'strict': true});
      expect(init['capabilities'], isEmpty);

      final run = jsonDecode(process.received[1]) as Map<String, Object?>;
      expect(run['type'], 'run');
      expect(run['all'], isFalse);
      final changes = run['changes']! as List<Object?>;
      expect(changes, hasLength(1));
      expect((changes.single! as Map)['path'], 'lib/a.dart');

      expect(result.findings, [
        Finding(
          rule: RuleId.parse('team/no-print'),
          severity: Severity.error,
          message: 'print found',
          location: Location(
            path('lib/a.dart'),
            const Position(1, 1),
            const Position(1, 1),
          ),
        ),
      ]);
      expect(process.killed, isTrue);
      expect(process.stdinClosed, isTrue);
    });

    test(
      'answers read from the snapshot; text is null when unreadable',
      () async {
        final contents = <int, String?>{};
        final factory = FakeCheckProcessFactory(
          create: () => FakeCheckProcess(
            onMessage: (message, process) async {
              switch (message) {
                case InitMessage():
                  return [
                    ReadyMessage(
                      protocol: customCheckProtocol,
                      rules: [
                        RuleDescriptor(
                          id: RuleId.parse('team/no-print'),
                          defaultSeverity: Severity.error,
                          summary: 'No print',
                        ),
                      ],
                    ),
                  ];
                case RunMessage():
                  return [
                    readRequest(),
                    readRequest(id: 2, path: 'lib/missing.dart'),
                    readRequest(id: 3, side: 'base'),
                    const DoneMessage(),
                  ];
                case ContentMessage(:final id, :final text):
                  contents[id] = text;
                  return const [];
              }
            },
          ),
        );

        await check(factory: factory).run(
          context(
            files: {
              'tool/check.dart': 'void main() {}',
              'lib/a.dart': 'print(1);',
            },
            baseFiles: const {},
          ),
        );

        expect(contents[1], 'print(1);');
        expect(contents[2], isNull);
        expect(contents[3], isNull);
      },
    );

    test('accepts a finding for a path inside the repo but outside the '
        'changeset', () async {
      final factory = FakeCheckProcessFactory(
        create: () => FakeCheckProcess(
          onMessage: wellBehavedScript(
            findings: [finding(path: 'lib/other.dart')],
          ),
        ),
      );

      final result = await check(factory: factory).run(
        context(
          files: {'tool/check.dart': '', 'lib/other.dart': ''},
          changes: [
            FileChange(path: path('lib/a.dart'), kind: ChangeKind.modified),
          ],
        ),
      );

      expect(result.findings.single.location.path, path('lib/other.dart'));
    });

    test(
      'passes all: true on the run message when constructed with all',
      () async {
        final factory = FakeCheckProcessFactory(
          create: () => FakeCheckProcess(onMessage: wellBehavedScript()),
        );

        await check(factory: factory, all: true).run(context());

        final run =
            jsonDecode(factory.last!.received[1]) as Map<String, Object?>;
        expect(run['all'], isTrue);
      },
    );
  });

  group('divergence', () {
    test('diverge before start does not spawn the child', () async {
      final factory = FakeCheckProcessFactory();
      final sut = check(factory: factory);

      await expectLater(
        sut.run(context(dirty: {'tool/check.dart'})),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            'custom check "team": source diverges from the snapshot at '
                'tool/check.dart. Commit the check source changes or check out '
                'the pushed revision, or pass --no-custom-checks.',
          ),
        ),
      );
      expect(factory.starts, isEmpty);
    });

    test('uses the pre-commit diverge message', () async {
      final factory = FakeCheckProcessFactory();

      await expectLater(
        check(
          factory: factory,
        ).run(context(entry: EntryKind.preCommit, dirty: {'tool/check.dart'})),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('Stage the check source changes'),
          ),
        ),
      );
    });

    test('uses the ci diverge message', () async {
      final factory = FakeCheckProcessFactory();

      await expectLater(
        check(factory: factory)
            .run(context(entry: EntryKind.ci, dirty: {'tool/check.dart'})),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('Commit or discard local changes'),
          ),
        ),
      );
    });

    test('discards findings when sources diverge after exit', () async {
      final factory = FakeCheckProcessFactory(
        create: () => FakeCheckProcess(
          onMessage: wellBehavedScript(findings: [finding()]),
        ),
      );

      await expectLater(
        check(factory: factory).run(
          context(
            divergentAnswers: [
              <String>{},
              {'tool/check.dart'},
            ],
          ),
        ),
        throwsA(isA<UsageException>()),
      );
      expect(factory.starts, hasLength(1));
      expect(factory.last!.killed, isTrue);
    });
  });

  group('Review Focus adversarial children', () {
    test('noisy stdout is a protocol error naming the check', () async {
      final factory = FakeCheckProcessFactory(
        create: () => FakeCheckProcess(
          onMessage: wellBehavedScript(rawAfterInit: ['hello from print']),
        ),
      );

      await expectLater(
        check(factory: factory).run(context()),
        throwsA(
          isA<InternalException>().having(
            (e) => e.message,
            'message',
            allOf(
              startsWith('custom check "team": protocol error:'),
              contains('hello from print'),
            ),
          ),
        ),
      );
      expect(factory.last!.killed, isTrue);
    });

    test('a hanging child times out, is killed, and fails closed', () async {
      final factory = FakeCheckProcessFactory(
        create: () => FakeCheckProcess(hangsUntilKilled: true),
      );

      await expectLater(
        check(
          factory: factory,
          timeout: const Duration(milliseconds: 50),
        ).run(context()),
        throwsA(
          isA<InternalException>().having(
            (e) => e.message,
            'message',
            'custom check "team": timed out after 50ms.',
          ),
        ),
      );
      expect(factory.last!.killed, isTrue);
    });

    test(
      'an undeclared rule is a protocol error; finding is not kept',
      () async {
        final factory = FakeCheckProcessFactory(
          create: () => FakeCheckProcess(
            onMessage: wellBehavedScript(
              findings: [finding(rule: 'team/other')],
            ),
          ),
        );

        await expectLater(
          check(factory: factory).run(context()),
          throwsA(
            isA<InternalException>().having(
              (e) => e.message,
              'message',
              contains('protocol error'),
            ),
          ),
        );
      },
    );

    test('a path outside the repository is a protocol error', () async {
      final factory = FakeCheckProcessFactory(
        create: () => FakeCheckProcess(
          onMessage: (message, process) async {
            switch (message) {
              case InitMessage():
                return [
                  ReadyMessage(
                    protocol: customCheckProtocol,
                    rules: [
                      RuleDescriptor(
                        id: RuleId.parse('team/no-print'),
                        defaultSeverity: Severity.error,
                        summary: 'x',
                      ),
                    ],
                  ),
                ];
              case RunMessage():
                process.emitRaw(
                  jsonEncode({
                    'type': 'finding',
                    'rule': 'team/no-print',
                    'path': '../secret',
                    'line': 1,
                    'column': 1,
                    'message': 'x',
                  }),
                );
                return [const DoneMessage()];
              case ContentMessage():
                return const [];
            }
          },
        ),
      );

      await expectLater(
        check(factory: factory).run(context()),
        throwsA(
          isA<InternalException>().having(
            (e) => e.message,
            'message',
            contains('protocol error'),
          ),
        ),
      );
    });

    test('a rule whose check segment differs is a protocol error', () async {
      final factory = FakeCheckProcessFactory(
        create: () => FakeCheckProcess(
          onMessage: wellBehavedScript(
            findings: [finding(rule: 'other/no-print')],
          ),
        ),
      );

      await expectLater(
        check(factory: factory).run(context()),
        throwsA(isA<InternalException>()),
      );
    });
  });

  group('process failures', () {
    test('child killed in finally after success', () async {
      final factory = FakeCheckProcessFactory();
      await check(factory: factory).run(context());
      expect(factory.last!.killed, isTrue);
    });

    test('non-zero exit before done is an internal error', () async {
      final factory = FakeCheckProcessFactory(
        create: () => FakeCheckProcess(
          exitCodeValue: 7,
          standardErrorValue: 'boom',
          onMessage: (message, process) async {
            switch (message) {
              case InitMessage():
                return [
                  ReadyMessage(
                    protocol: customCheckProtocol,
                    rules: [
                      RuleDescriptor(
                        id: RuleId.parse('team/no-print'),
                        defaultSeverity: Severity.error,
                        summary: 'x',
                      ),
                    ],
                  ),
                ];
              case RunMessage():
                return const [];
              case ContentMessage():
                return const [];
            }
          },
        ),
      );

      await expectLater(
        check(factory: factory).run(context()),
        throwsA(
          isA<InternalException>().having(
            (e) => e.message,
            'message',
            allOf(contains('exited with code 7'), contains('boom')),
          ),
        ),
      );
    });

    test('exit 0 without done is an internal error', () async {
      final factory = FakeCheckProcessFactory(
        create: () => FakeCheckProcess(
          onMessage: (message, process) async {
            switch (message) {
              case InitMessage():
                return [
                  ReadyMessage(
                    protocol: customCheckProtocol,
                    rules: [
                      RuleDescriptor(
                        id: RuleId.parse('team/no-print'),
                        defaultSeverity: Severity.error,
                        summary: 'x',
                      ),
                    ],
                  ),
                ];
              case RunMessage():
                return const [];
              case ContentMessage():
                return const [];
            }
          },
        ),
      );

      await expectLater(
        check(factory: factory).run(context()),
        throwsA(
          isA<InternalException>().having(
            (e) => e.message,
            'message',
            'custom check "team": exited before done.',
          ),
        ),
      );
    });

    test('more than 10000 findings is a protocol error', () async {
      final factory = FakeCheckProcessFactory(
        create: () => FakeCheckProcess(
          onMessage: wellBehavedScript(
            findings: [
              for (var i = 0; i < maxFindingsPerCustomCheck + 1; i++)
                finding(message: 'f$i'),
            ],
          ),
        ),
      );

      await expectLater(
        check(factory: factory).run(context()),
        throwsA(
          isA<InternalException>().having(
            (e) => e.message,
            'message',
            contains('protocol error'),
          ),
        ),
      );
    });

    test('missing source in the snapshot is an internal error', () async {
      await expectLater(
        check().run(context(files: const {'lib/a.dart': ''})),
        throwsA(
          isA<InternalException>().having(
            (e) => e.message,
            'message',
            'custom check "team": source "tool/check.dart" is missing '
                'from the snapshot.',
          ),
        ),
      );
    });
  });
}

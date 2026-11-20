import 'package:stagelatch/src/checks/format/format_check.dart';
import 'package:stagelatch/src/checks/format/format_settings.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/fix.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_dart_toolchain.dart';
import '../../support/fake_snapshot_files.dart';

const _rule = RuleId('format', 'unformatted');

Future<(CheckResult, FakeCheckContext, FakeDartToolchain)> _run(
  Map<String, Object> files, {
  Map<String, String> formatted = const {},
  Set<String> unparseable = const {},
  List<FileChange>? changes,
  Map<String, FileMode> modes = const {},
  FormatSettings settings = const FormatSettings(),
  EntryKind entry = EntryKind.preCommit,
}) async {
  final dart = FakeDartToolchain(
    formatted: formatted,
    unparseable: unparseable,
  );
  final context = FakeCheckContext(
    entry: entry,
    snapshot: FakeSnapshotFiles(files, modes: modes),
    changes: ChangeSet(
      changes ??
          [
            for (final path in files.keys)
              FileChange(path: RepoPath(path), kind: ChangeKind.modified),
          ],
    ),
    dart: dart,
    settings: [settings],
  );
  final result = await const FormatCheck().run(context);
  return (result, context, dart);
}

void main() {
  test('declares one fixable rule in the fix phase', () {
    const check = FormatCheck();

    expect(check.id, 'format');
    expect(check.phase, CheckPhase.fix);
    expect(check.rules.single.id, _rule);
    expect(check.rules.single.fixable, isTrue);
    expect(check.rules.single.defaultSeverity, Severity.error);
  });

  test('an unformatted file yields a finding at the first difference and a '
      'fix', () async {
    final (result, _, _) = await _run(
      {'lib/a.dart': 'void main( ) {}\n'},
      formatted: {'lib/a.dart': 'void main() {}\n'},
    );

    expect(result.findings, [
      Finding(
        rule: _rule,
        severity: Severity.error,
        message: 'File is not formatted.',
        location: Location(
          RepoPath('lib/a.dart'),
          const Position(1, 11),
          const Position(1, 11),
        ),
      ),
    ]);
    expect(result.fixes, [
      Fix(
        rule: _rule,
        path: RepoPath('lib/a.dart'),
        content: 'void main() {}\n',
      ),
    ]);
  });

  test(
    'a formatted file, a deleted file and a non-Dart file yield nothing',
    () async {
      final (result, _, dart) = await _run(
        {'lib/ok.dart': 'void main() {}\n', 'README.md': 'x  y\n'},
        changes: [
          FileChange(path: RepoPath('lib/ok.dart'), kind: ChangeKind.modified),
          FileChange(path: RepoPath('README.md'), kind: ChangeKind.modified),
          FileChange(path: RepoPath('lib/gone.dart'), kind: ChangeKind.deleted),
        ],
      );

      expect(result.findings, isEmpty);
      expect(dart.formatCalls, [RepoPath('lib/ok.dart')]);
    },
  );

  test('an unparseable file yields nothing', () async {
    final (result, _, _) = await _run(
      {'lib/a.dart': 'void main( {\n'},
      unparseable: {'lib/a.dart'},
    );

    expect(result.findings, isEmpty);
    expect(result.fixes, isEmpty);
  });

  test('a symlink or a submodule entry is not formatted', () async {
    final (_, _, dart) = await _run(
      {'lib/link.dart': 'a.dart', 'lib/sub.dart': ''},
      modes: {
        'lib/link.dart': FileMode.symlink,
        'lib/sub.dart': FileMode.gitlink,
      },
    );

    expect(dart.formatCalls, isEmpty);
  });

  test('the fix is returned whatever the entry; the pipeline decides '
      'whether to apply it', () async {
    final (result, _, _) = await _run(
      {'lib/a.dart': 'x  ;\n'},
      formatted: {'lib/a.dart': 'x;\n'},
      entry: EntryKind.prePush,
    );

    expect(result.findings, hasLength(1));
    expect(result.fixes, hasLength(1));
  });

  test('format.fix false returns the finding without a fix', () async {
    final (result, _, _) = await _run(
      {'lib/a.dart': 'x  ;\n'},
      formatted: {'lib/a.dart': 'x;\n'},
      settings: const FormatSettings(fix: false),
    );

    expect(result.findings, hasLength(1));
    expect(result.fixes, isEmpty);
  });

  test('findings come out in path order', () async {
    final (result, _, _) = await _run(
      {'lib/b.dart': 'b  ;\n', 'lib/a.dart': 'a  ;\n'},
      formatted: {'lib/a.dart': 'a;\n', 'lib/b.dart': 'b;\n'},
    );

    expect(result.findings.map((f) => f.location.path.value), [
      'lib/a.dart',
      'lib/b.dart',
    ]);
  });

  test('a disabled rule does no work', () async {
    final dart = FakeDartToolchain();
    final context = FakeCheckContext(
      snapshot: FakeSnapshotFiles({'lib/a.dart': 'x'}),
      changes: ChangeSet([
        FileChange(path: RepoPath('lib/a.dart'), kind: ChangeKind.modified),
      ]),
      dart: dart,
      enabled: const {},
    );

    final result = await const FormatCheck().run(context);

    expect(result.findings, isEmpty);
    expect(context.dartAccessed, isFalse);
  });
}

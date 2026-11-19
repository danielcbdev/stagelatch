import 'package:stagelatch/src/checks/analyze/analyze_check.dart';
import 'package:stagelatch/src/checks/analyze/analyze_settings.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_dart_toolchain.dart';
import '../../support/fake_snapshot_files.dart';

DartDiagnostic _diagnostic(
  String code,
  DiagnosticSeverity severity, {
  int line = 1,
  String message = 'm',
}) => DartDiagnostic(
  location: Location(
    RepoPath('lib/a.dart'),
    Position(line, 1),
    Position(line, 4),
  ),
  code: code,
  severity: severity,
  message: message,
);

Future<(List<Finding>, FakeCheckContext, FakeDartToolchain)> _run(
  List<DartDiagnostic> diagnostics, {
  AnalyzeSettings settings = const AnalyzeSettings(),
  List<String> changed = const ['lib/a.dart'],
}) async {
  final dart = FakeDartToolchain(diagnostics: diagnostics);
  final context = FakeCheckContext(
    snapshot: FakeSnapshotFiles({
      'pubspec.yaml': 'name: app\n',
      'lib/a.dart': '',
      'README.md': '',
    }),
    changes: ChangeSet([
      for (final path in changed)
        FileChange(path: RepoPath(path), kind: ChangeKind.modified),
    ]),
    packages: PackageMap(const [DartPackage(root: null, name: 'app')]),
    dart: dart,
    settings: [settings],
  );
  final result = await const AnalyzeCheck().run(context);
  expect(result.fixes, isEmpty);
  return (result.findings, context, dart);
}

void main() {
  test('declares dynamic rules in the verify phase', () {
    const check = AnalyzeCheck();

    expect(check.id, 'analyze');
    expect(check.phase, CheckPhase.verify);
    expect(check.hasDynamicRules, isTrue);
    expect(check.rules, isEmpty);
  });

  test('severity mapping follows fail_on', () async {
    final (findings, _, _) = await _run([
      _diagnostic('undefined_identifier', DiagnosticSeverity.error),
      _diagnostic('unused_import', DiagnosticSeverity.warning, line: 2),
      _diagnostic('avoid_print', DiagnosticSeverity.info, line: 3),
    ], settings: const AnalyzeSettings(failOn: {DiagnosticSeverity.error}));

    expect(findings.map((f) => (f.rule.toString(), f.severity)), [
      ('analyze/undefined_identifier', Severity.error),
      ('analyze/unused_import', Severity.warning),
    ]);
  });

  test(
    'info is reported only when listed in fail_on, then as an error',
    () async {
      final (findings, _, _) = await _run(
        [_diagnostic('avoid_print', DiagnosticSeverity.info)],
        settings: const AnalyzeSettings(
          failOn: {
            DiagnosticSeverity.error,
            DiagnosticSeverity.warning,
            DiagnosticSeverity.info,
          },
        ),
      );

      expect(findings.single.severity, Severity.error);
    },
  );

  test("the message and range are the analyzer's", () async {
    final (findings, _, _) = await _run([
      _diagnostic(
        'invalid_assignment',
        DiagnosticSeverity.error,
        message: "A value of type 'String' can't be assigned.",
      ),
    ]);

    expect(
      findings.single,
      Finding(
        rule: const RuleId('analyze', 'invalid_assignment'),
        severity: Severity.error,
        message: "A value of type 'String' can't be assigned.",
        location: Location(
          RepoPath('lib/a.dart'),
          const Position(1, 1),
          const Position(1, 4),
        ),
      ),
    );
  });

  test('the files of the scope are requested from the toolchain', () async {
    final (_, _, dart) = await _run(const []);

    expect(dart.diagnoseCalls, [
      {RepoPath('lib/a.dart')},
    ]);
  });

  test('no changed Dart, pubspec or analysis_options file means the '
      'toolchain is never touched', () async {
    final (findings, context, _) = await _run(const [], changed: ['README.md']);

    expect(findings, isEmpty);
    expect(context.dartAccessed, isFalse);
  });
}

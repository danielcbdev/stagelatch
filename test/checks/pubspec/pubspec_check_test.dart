import 'package:stagelatch/src/checks/pubspec/pubspec_check.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_snapshot_files.dart';

const _violating =
    'name: app\ndependencies:\n  ui:\n    path: ../../../ui\n'
    'dependency_overrides:\n  intl: 0.19.0\n';

/// Runs the check over [files]. Every file counts as modified unless
/// [changed] narrows that down; [deleted] paths are not in the snapshot.
Future<List<Finding>> _run(
  Map<String, Object> files, {
  List<String>? changed,
  List<String> deleted = const [],
  Set<RuleId>? enabled,
}) async {
  final context = FakeCheckContext(
    snapshot: FakeSnapshotFiles(files),
    changes: ChangeSet([
      for (final path in changed ?? files.keys)
        FileChange(path: RepoPath(path), kind: ChangeKind.modified),
      for (final path in deleted)
        FileChange(path: RepoPath(path), kind: ChangeKind.deleted),
    ]),
    enabled: enabled,
  );
  final result = await const PubspecCheck().run(context);
  expect(result.fixes, isEmpty);
  expect(context.dartAccessed, isFalse);
  return result.findings;
}

void main() {
  group('PubspecCheck', () {
    test('declares its identity and rules', () {
      const check = PubspecCheck();

      expect(check.id, 'pubspec');
      expect(check.phase, CheckPhase.verify);
      expect(check.hasDynamicRules, isFalse);
      expect(check.rules.map((rule) => rule.id.toString()), [
        'pubspec/path-dependency',
        'pubspec/dependency-overrides',
        'pubspec/unparseable',
      ]);
      expect(
        check.rules.every((rule) => rule.defaultSeverity == Severity.error),
        isTrue,
      );
      expect(check.rules.every((rule) => !rule.fixable), isTrue);
      expect(check.rules.every((rule) => rule.summary.endsWith('.')), isTrue);
    });

    test('reports both rules for a violating pubspec', () async {
      final findings = await _run({'pubspec.yaml': _violating});

      expect(findings.map((finding) => finding.rule), [
        pathDependencyRule,
        dependencyOverridesRule,
      ]);
    });

    test('a clean pubspec yields nothing', () async {
      final findings = await _run({
        'pubspec.yaml': 'name: app\ndependencies:\n  http: ^1.2.0\n',
      });

      expect(findings, isEmpty);
    });

    test('a path to another package of the snapshot is allowed', () async {
      final findings = await _run(
        {
          'app/pubspec.yaml':
              'name: app\ndependencies:\n  ui:\n    path: ../packages/ui\n',
          'packages/ui/pubspec.yaml': 'name: ui\n',
        },
        changed: ['app/pubspec.yaml'],
      );

      expect(findings, isEmpty);
    });

    test('a pubspec that did not change is not inspected', () async {
      final findings = await _run(
        {'pubspec.yaml': _violating, 'lib/a.dart': ''},
        changed: ['lib/a.dart'],
      );

      expect(findings, isEmpty);
    });

    test('a deleted pubspec is not inspected', () async {
      final findings = await _run({}, deleted: ['pubspec.yaml']);

      expect(findings, isEmpty);
    });

    test('every changed pubspec is inspected, wherever it is', () async {
      final findings = await _run({
        'pubspec.yaml': _violating,
        'packages/ui/pubspec.yaml': _violating,
      });

      expect(findings.map((finding) => finding.location.path.value).toSet(), {
        'pubspec.yaml',
        'packages/ui/pubspec.yaml',
      });
      expect(findings, hasLength(4));
    });

    test('a file merely named like a pubspec is not one', () async {
      final findings = await _run({'docs/my_pubspec.yaml': _violating});

      expect(findings, isEmpty);
    });

    test('invalid YAML yields pubspec/unparseable and nothing else', () async {
      final findings = await _run({
        'pubspec.yaml': 'name: app\ndependencies: [a, b\n',
      });

      expect(findings.single.rule, unparseableRule);
      expect(findings.single.severity, Severity.error);
      expect(
        findings.single.message,
        startsWith('pubspec.yaml is not valid YAML: '),
      );
      expect(findings.single.message, endsWith('.'));
      expect(findings.single.location.path, RepoPath('pubspec.yaml'));
    });

    test('a pubspec whose root is not a map is unparseable', () async {
      final asList = await _run({'pubspec.yaml': '- a\n- b\n'});
      final empty = await _run({'pubspec.yaml': ''});

      expect(
        asList.single.message,
        'pubspec.yaml is not valid YAML: expected a map at the top level.',
      );
      expect(
        asList.single.location,
        Location.wholeFile(RepoPath('pubspec.yaml')),
      );
      expect(empty.single.rule, unparseableRule);
    });

    test('a pubspec that is not text is unparseable', () async {
      final findings = await _run({
        'pubspec.yaml': [0x00, 0x01],
      });

      expect(
        findings.single.message,
        'pubspec.yaml is not valid YAML: the file is not readable text.',
      );
    });

    test('dependencies: null is fine', () async {
      final findings = await _run({
        'pubspec.yaml': 'name: app\ndependencies:\ndev_dependencies:\n',
      });

      expect(findings, isEmpty);
    });

    test('a changed pubspec_overrides.yaml is reported at 1:1', () async {
      final findings = await _run({
        'packages/ui/pubspec_overrides.yaml': 'dependency_overrides:\n',
      });

      expect(findings, [
        Finding(
          rule: dependencyOverridesRule,
          severity: Severity.error,
          message: 'pubspec_overrides.yaml must not be committed.',
          location: Location.wholeFile(
            RepoPath('packages/ui/pubspec_overrides.yaml'),
          ),
        ),
      ]);
    });

    test('a deleted pubspec_overrides.yaml is not reported', () async {
      final findings = await _run({}, deleted: ['pubspec_overrides.yaml']);

      expect(findings, isEmpty);
    });

    test('a disabled rule produces nothing', () async {
      final onlyOverrides = await _run(
        {'pubspec.yaml': _violating},
        enabled: {dependencyOverridesRule},
      );
      final onlyPaths = await _run(
        {'pubspec.yaml': _violating, 'pubspec_overrides.yaml': ''},
        enabled: {pathDependencyRule},
      );
      final noUnparseable = await _run(
        {'pubspec.yaml': '- a\n'},
        enabled: {pathDependencyRule, dependencyOverridesRule},
      );

      expect(onlyOverrides.single.rule, dependencyOverridesRule);
      expect(onlyPaths.single.rule, pathDependencyRule);
      expect(noUnparseable, isEmpty);
    });
  });
}

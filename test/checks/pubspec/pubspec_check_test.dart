import 'package:stagelatch/src/checks/pubspec/pubspec_check.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_settings.dart';
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
///
/// [base] and [targetBranch] are what the rules that compare with the base
/// need, and [renamed] maps a new path to the path it had in the base.
Future<List<Finding>> _run(
  Map<String, Object> files, {
  List<String>? changed,
  List<String> deleted = const [],
  Set<RuleId>? enabled,
  PubspecSettings settings = const PubspecSettings(),
  Map<String, Object>? base,
  String? targetBranch,
  Map<String, String> renamed = const {},
}) async {
  final context = FakeCheckContext(
    snapshot: FakeSnapshotFiles(files),
    base: base == null ? null : FakeSnapshotFiles(base),
    targetBranch: targetBranch,
    changes: ChangeSet([
      for (final path in changed ?? files.keys)
        if (renamed.containsKey(path))
          FileChange(
            path: RepoPath(path),
            kind: ChangeKind.renamed,
            previousPath: RepoPath(renamed[path]!),
          )
        else
          FileChange(path: RepoPath(path), kind: ChangeKind.modified),
      for (final path in deleted)
        FileChange(path: RepoPath(path), kind: ChangeKind.deleted),
    ]),
    enabled: enabled,
    settings: [settings],
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
        'pubspec/unpinned-git',
        'pubspec/build-number-regression',
        'pubspec/lockfile-out-of-sync',
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

    group('unpinned-git', () {
      const git =
          'name: app\ndependencies:\n  ui:\n    git:\n'
          '      url: https://example.com/ui.git\n      ref: main\n';

      test('require_sha comes from the settings', () async {
        final lax = await _run({'pubspec.yaml': git});
        final strict = await _run({
          'pubspec.yaml': git,
        }, settings: const PubspecSettings(requireSha: true));

        expect(lax, isEmpty);
        expect(strict.single.rule, unpinnedGitRule);
      });

      test('a disabled rule produces nothing', () async {
        final findings = await _run(
          {'pubspec.yaml': 'name: app\ndependencies:\n  ui:\n    git: u\n'},
          enabled: {pathDependencyRule},
        );

        expect(findings, isEmpty);
      });
    });

    group('build-number-regression', () {
      bool onRelease(String branch) => branch.startsWith('release/');
      final settings = PubspecSettings(monotonicBuildNumber: [onRelease]);

      Future<List<Finding>> run({
        String? targetBranch = 'release/1.2',
        Map<String, Object>? base = const {
          'pubspec.yaml': 'name: app\nversion: 1.2.0+10\n',
        },
        Map<String, Object> files = const {
          'pubspec.yaml': 'name: app\nversion: 1.1.9+11\n',
        },
        Map<String, String> renamed = const {},
        Set<RuleId>? enabled,
      }) => _run(
        files,
        settings: settings,
        base: base,
        targetBranch: targetBranch,
        renamed: renamed,
        enabled: enabled,
      );

      test('is reported on a branch that matches a configured glob', () async {
        final findings = await run();

        expect(findings.single.rule, buildNumberRegressionRule);
        expect(
          findings.single.message,
          'Version went backwards: 1.2.0+10 -> 1.1.9+11.',
        );
        expect(findings.single.location.path, RepoPath('pubspec.yaml'));
      });

      test('does not apply on a branch that matches no glob', () async {
        expect(await run(targetBranch: 'main'), isEmpty);
      });

      test('does not apply when the target branch is unknown', () async {
        expect(await run(targetBranch: null), isEmpty);
      });

      test('does not apply with no glob configured', () async {
        final findings = await _run(
          {'pubspec.yaml': 'name: app\nversion: 1.1.9+11\n'},
          base: {'pubspec.yaml': 'name: app\nversion: 1.2.0+10\n'},
          targetBranch: 'release/1.2',
        );

        expect(findings, isEmpty);
      });

      test('no base, or no pubspec in the base, is not a regression', () async {
        expect(await run(base: null), isEmpty);
        expect(await run(base: const {'README.md': ''}), isEmpty);
      });

      test('a renamed pubspec is compared with its previous path', () async {
        final findings = await run(
          files: {'app/pubspec.yaml': 'name: app\nversion: 1.1.9+11\n'},
          base: {'old/pubspec.yaml': 'name: app\nversion: 1.2.0+10\n'},
          renamed: {'app/pubspec.yaml': 'old/pubspec.yaml'},
        );

        expect(findings.single.location.path, RepoPath('app/pubspec.yaml'));
      });

      test('a disabled rule produces nothing', () async {
        expect(await run(enabled: {pathDependencyRule}), isEmpty);
      });
    });

    group('lockfile-out-of-sync', () {
      const pubspec = 'name: app\ndependencies:\n  http: ^1.2.0\n';
      const staleLock =
          'packages:\n  http:\n    dependency: "direct main"\n'
          '    description:\n      name: http\n    source: hosted\n'
          '    version: "0.13.6"\n';
      const goodLock =
          'packages:\n  http:\n    dependency: "direct main"\n'
          '    description:\n      name: http\n    source: hosted\n'
          '    version: "1.2.1"\n';

      test('a changed pubspec is compared with its sibling lock', () async {
        final findings = await _run(
          {'pubspec.yaml': pubspec, 'pubspec.lock': staleLock},
          changed: ['pubspec.yaml'],
        );

        expect(findings.single.rule, lockfileOutOfSyncRule);
        expect(findings.single.location.path, RepoPath('pubspec.yaml'));
      });

      test('a changed lock triggers its unchanged pubspec', () async {
        final findings = await _run(
          {'pubspec.yaml': pubspec, 'pubspec.lock': staleLock},
          changed: ['pubspec.lock'],
        );

        expect(findings.single.rule, lockfileOutOfSyncRule);
        expect(findings.single.location.path, RepoPath('pubspec.yaml'));
      });

      test('both changed are compared once', () async {
        final findings = await _run({
          'pubspec.yaml': pubspec,
          'pubspec.lock': staleLock,
        });

        expect(findings, hasLength(1));
      });

      test('a lock that satisfies the pubspec yields nothing', () async {
        final findings = await _run({
          'pubspec.yaml': pubspec,
          'pubspec.lock': goodLock,
        });

        expect(findings, isEmpty);
      });

      test('no sibling pubspec.lock means the rule is silent', () async {
        final findings = await _run({'pubspec.yaml': pubspec});
        final elsewhere = await _run({
          'pubspec.yaml': pubspec,
          'other/pubspec.lock': staleLock,
        });

        expect(findings, isEmpty);
        expect(elsewhere, isEmpty);
      });

      test('the sibling is in the same directory as the pubspec', () async {
        final findings = await _run({
          'packages/ui/pubspec.yaml': pubspec,
          'packages/ui/pubspec.lock': staleLock,
        });

        expect(
          findings.single.location.path,
          RepoPath('packages/ui/pubspec.yaml'),
        );
      });

      test('a lock that is not valid YAML is left to pub', () async {
        final findings = await _run({
          'pubspec.yaml': pubspec,
          'pubspec.lock': 'packages: [a, b\n',
        });

        expect(findings, isEmpty);
      });

      test('a changed lock whose pubspec is not valid says nothing', () async {
        final findings = await _run(
          {
            'pubspec.yaml': 'name: app\ndependencies: [a, b\n',
            'pubspec.lock': staleLock,
          },
          changed: ['pubspec.lock'],
        );

        expect(findings, isEmpty);
      });

      test('a deleted lock is not compared', () async {
        final findings = await _run(
          {'pubspec.yaml': pubspec},
          changed: ['pubspec.yaml'],
          deleted: ['pubspec.lock'],
        );

        expect(findings, isEmpty);
      });

      test('a disabled rule produces nothing', () async {
        final findings = await _run(
          {'pubspec.yaml': pubspec, 'pubspec.lock': staleLock},
          enabled: {pathDependencyRule},
        );

        expect(findings, isEmpty);
      });
    });
  });
}

import 'package:stagelatch/src/checks/assets/assets_check.dart';
import 'package:stagelatch/src/checks/assets/assets_rules.dart';
import 'package:stagelatch/src/checks/assets/assets_settings.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_snapshot_files.dart';

const _pubspec = 'name: app\nflutter:\n  assets:\n    - assets/img/\n';

/// 612.4 KB: over the default limit of 500 KB.
final _large = List<int>.filled(627098, 0);

/// Runs the check over [files]. Every file counts as modified unless
/// [changed] narrows that down; [deleted] paths are not in the snapshot.
Future<List<Finding>> _run(
  Map<String, Object> files, {
  List<String>? changed,
  List<String> deleted = const [],
  AssetsSettings? settings,
  List<DartPackage>? packages,
  Set<RuleId>? enabled,
  Map<String, FileMode> modes = const {},
}) async {
  final context = FakeCheckContext(
    snapshot: FakeSnapshotFiles(files, modes: modes),
    changes: ChangeSet([
      for (final path in changed ?? files.keys)
        FileChange(path: RepoPath(path), kind: ChangeKind.modified),
      for (final path in deleted)
        FileChange(path: RepoPath(path), kind: ChangeKind.deleted),
    ]),
    packages: PackageMap(
      packages ?? [const DartPackage(root: null, name: 'app')],
    ),
    enabled: enabled,
    settings: [settings ?? AssetsSettings()],
  );
  final result = await const AssetsCheck().run(context);
  expect(result.fixes, isEmpty);
  expect(context.dartAccessed, isFalse);
  return result.findings;
}

void main() {
  group('AssetsCheck', () {
    test('declares its identity and rules', () {
      const check = AssetsCheck();

      expect(check.id, 'assets');
      expect(check.phase, CheckPhase.verify);
      expect(check.hasDynamicRules, isFalse);
      expect(check.rules.map((rule) => rule.id.toString()), [
        'assets/missing',
        'assets/undeclared',
        'assets/max-file-size',
      ]);
      expect(
        check.rules.every((rule) => rule.defaultSeverity == Severity.error),
        isTrue,
      );
      expect(check.rules.every((rule) => rule.summary.endsWith('.')), isTrue);
    });

    test('declared file absent from the snapshot', () async {
      final findings = await _run({
        'pubspec.yaml':
            'name: app\nflutter:\n  assets:\n    - assets/img/logo.png\n',
      });

      expect(findings, hasLength(1));
      expect(findings.single.rule, missingRule);
      expect(findings.single.severity, Severity.error);
      expect(
        findings.single.message,
        'Asset "assets/img/logo.png" is declared but does not exist.',
      );
      expect(findings.single.location.path, RepoPath('pubspec.yaml'));
      expect(findings.single.location.start, const Position(4, 7));
    });

    test('declared directory with no file in the snapshot', () async {
      final findings = await _run({'pubspec.yaml': _pubspec});

      expect(
        findings.single.message,
        'Asset "assets/img/" is declared but does not exist.',
      );
    });

    test('declared directory that only has variant subdirectories is not '
        'missing', () async {
      final findings = await _run(
        {'pubspec.yaml': _pubspec, 'assets/img/2.0x/a.png': 'x'},
        changed: ['pubspec.yaml'],
      );

      expect(findings, isEmpty);
    });

    test('a directory holding only a nested directory is missing', () async {
      final findings = await _run(
        {'pubspec.yaml': _pubspec, 'assets/img/icons/a.png': 'x'},
        changed: ['pubspec.yaml'],
      );

      expect(findings.single.rule, missingRule);
    });

    test('a declared font that does not exist is missing', () async {
      final findings = await _run({
        'pubspec.yaml':
            'name: app\nflutter:\n  fonts:\n    - family: B\n'
            '      fonts:\n        - asset: fonts/B.ttf\n',
      });

      expect(
        findings.single.message,
        'Asset "fonts/B.ttf" is declared but does not exist.',
      );
    });

    test('changed file under a root that is not declared', () async {
      final findings = await _run(
        {
          'pubspec.yaml': _pubspec,
          'assets/img/a.png': 'x',
          'assets/b.txt': 'x',
        },
        changed: ['assets/b.txt'],
      );

      expect(findings, hasLength(1));
      expect(findings.single.rule, undeclaredRule);
      expect(
        findings.single.message,
        'File is under "assets/" but is not declared in pubspec.yaml.',
      );
      expect(
        findings.single.location,
        Location.wholeFile(RepoPath('assets/b.txt')),
      );
    });

    test('a declared file is not undeclared, and an unchanged one is not '
        'looked at', () async {
      final findings = await _run(
        {
          'pubspec.yaml': _pubspec,
          'assets/img/a.png': 'x',
          'assets/other.txt': 'x',
        },
        changed: ['assets/img/a.png'],
      );

      expect(findings, isEmpty);
    });

    test('file over the limit', () async {
      final findings = await _run(
        {'pubspec.yaml': _pubspec, 'assets/img/big.png': _large},
        changed: ['assets/img/big.png'],
      );

      expect(findings, hasLength(1));
      expect(findings.single.rule, maxFileSizeRule);
      expect(
        findings.single.message,
        'File is 612.4KB, larger than the limit of 500KB.',
      );
      expect(
        findings.single.location,
        Location.wholeFile(RepoPath('assets/img/big.png')),
      );
    });

    test('a file exactly at the limit passes', () async {
      final findings = await _run(
        {
          'pubspec.yaml': _pubspec,
          'assets/img/ok.png': List<int>.filled(500 * 1024, 0),
        },
        changed: ['assets/img/ok.png'],
      );

      expect(findings, isEmpty);
    });

    test(
      'an undeclared file over the limit is reported by both rules',
      () async {
        final findings = await _run(
          {
            'pubspec.yaml': _pubspec,
            'assets/img/a.png': 'x',
            'assets/big.bin': _large,
          },
          changed: ['assets/big.bin'],
        );

        expect(findings.map((f) => f.rule), [undeclaredRule, maxFileSizeRule]);
      },
    );

    test('the limit and the roots come from the settings', () async {
      final findings = await _run(
        {
          'pubspec.yaml': 'name: app\nflutter:\n  assets:\n    - res/\n',
          'res/a.png': List<int>.filled(2000, 0),
          'assets/b.png': List<int>.filled(2000, 0),
        },
        changed: ['res/a.png', 'assets/b.png'],
        settings: AssetsSettings(maxFileSize: 1500, roots: [RepoPath('res')]),
      );

      expect(
        findings.single.message,
        'File is 2.0KB, larger than the limit of 1.5KB.',
      );
      expect(findings.single.location.path, RepoPath('res/a.png'));
    });

    test('a file outside every root is not an asset', () async {
      final findings = await _run(
        {'pubspec.yaml': _pubspec, 'lib/a.dart': 'x', 'assets/img/a.png': 'x'},
        changed: ['lib/a.dart'],
      );

      expect(findings, isEmpty);
    });

    test('assets.ignore exempts a path from all three rules', () async {
      final findings = await _run(
        {
          'pubspec.yaml':
              'name: app\nflutter:\n  assets:\n    - assets/videos/\n'
              '    - assets/skip/gone.png\n',
          'assets/videos/demo.mp4': _large,
          'assets/loose/clip.mp4': _large,
        },
        settings: AssetsSettings(
          ignore: [
            (path) => path.startsWith('assets/videos/'),
            (path) => path.startsWith('assets/skip/'),
            (path) => path.startsWith('assets/loose/'),
          ],
        ),
      );

      expect(findings, isEmpty);
    });

    test('paths are resolved relative to the package of the pubspec', () async {
      final findings = await _run(
        {
          'packages/ui/pubspec.yaml': _pubspec,
          'packages/ui/assets/img/a.png': 'x',
          'packages/ui/assets/b.txt': 'x',
          'assets/elsewhere.txt': 'x',
        },
        packages: [DartPackage(root: RepoPath('packages/ui'), name: 'ui')],
        changed: ['packages/ui/assets/b.txt', 'assets/elsewhere.txt'],
      );

      expect(findings, hasLength(1));
      expect(
        findings.single.location.path,
        RepoPath('packages/ui/assets/b.txt'),
      );
      expect(
        findings.single.message,
        'File is under "assets/" but is not declared in pubspec.yaml.',
      );
    });

    test(
      'deleting an asset triggers the missing rule for its declaration',
      () async {
        final findings = await _run(
          {
            'pubspec.yaml':
                'name: app\nflutter:\n  assets:\n    - assets/img/logo.png\n',
          },
          changed: const [],
          deleted: ['assets/img/logo.png'],
        );

        expect(
          findings.single.message,
          'Asset "assets/img/logo.png" is declared but does not exist.',
        );
        expect(findings.single.location.path, RepoPath('pubspec.yaml'));
      },
    );

    test('deleting a file nothing declares says nothing', () async {
      final findings = await _run(
        {'pubspec.yaml': _pubspec, 'assets/img/a.png': 'x'},
        changed: const [],
        deleted: ['assets/old.txt'],
      );

      expect(findings, isEmpty);
    });

    test('a changed pubspec alone checks every declaration', () async {
      final findings = await _run(
        {'pubspec.yaml': _pubspec, 'assets/img/a.png': 'x'},
        changed: ['pubspec.yaml'],
      );

      expect(findings, isEmpty);
    });

    test('a file is reported once even when its pubspec changed too', () async {
      final findings = await _run({
        'pubspec.yaml': _pubspec,
        'assets/img/a.png': 'x',
        'assets/b.txt': 'x',
      });

      expect(findings.map((f) => f.rule), [undeclaredRule]);
    });

    test('symlinks and submodule entries under a root are skipped', () async {
      final findings = await _run(
        {
          'pubspec.yaml': _pubspec,
          'assets/img/a.png': 'x',
          'assets/link': 'a.png',
          'assets/mod': '',
        },
        changed: ['assets/link', 'assets/mod'],
        modes: {
          'assets/link': FileMode.symlink,
          'assets/mod': FileMode.gitlink,
        },
      );

      expect(findings, isEmpty);
    });

    test(
      'a pubspec that is not valid YAML is left to the pubspec check',
      () async {
        final findings = await _run({
          'pubspec.yaml': 'name: app\nflutter: [a, b\n',
          'assets/b.txt': 'x',
        });

        expect(findings, isEmpty);
      },
    );

    test(
      'a package without a flutter section has no declared assets',
      () async {
        final findings = await _run(
          {'pubspec.yaml': 'name: app\n', 'assets/b.txt': 'x'},
          changed: ['assets/b.txt'],
        );

        expect(findings.single.rule, undeclaredRule);
      },
    );

    test('a disabled rule produces nothing', () async {
      final files = {
        'pubspec.yaml':
            'name: app\nflutter:\n  assets:\n    - assets/gone.png\n',
        'assets/big.bin': _large,
      };

      Future<List<RuleId>> only(RuleId rule) async => [
        for (final finding in await _run(files, enabled: {rule})) finding.rule,
      ];

      expect(await only(missingRule), [missingRule]);
      expect(await only(undeclaredRule), [undeclaredRule]);
      expect(await only(maxFileSizeRule), [maxFileSizeRule]);
    });
  });
}

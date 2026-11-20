import 'package:stagelatch/src/checks/sensitive_files/sensitive_files_check.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_snapshot_files.dart';

const _signing = 'Signing material must not be committed.';
const _credentials = 'Credentials file must not be committed.';
const _serviceAccount =
    '{"type": "service_account", "private_key": "SECRET", "client_id": "1"}';

Future<List<Finding>> _run(
  Map<String, Object> files, {
  List<FileChange>? changes,
  Map<String, FileMode> modes = const {},
  Set<RuleId>? enabled,
}) async {
  final context = FakeCheckContext(
    snapshot: FakeSnapshotFiles(files, modes: modes),
    changes: ChangeSet(
      changes ??
          [
            for (final path in files.keys)
              FileChange(path: RepoPath(path), kind: ChangeKind.added),
          ],
    ),
    enabled: enabled,
  );
  final result = await const SensitiveFilesCheck().run(context);
  expect(result.fixes, isEmpty);
  expect(context.dartAccessed, isFalse);
  return result.findings;
}

Finding _finding(String rule, String path, String message) => Finding(
  rule: RuleId('sensitive-files', rule),
  severity: Severity.error,
  message: message,
  location: Location.wholeFile(RepoPath(path)),
);

void main() {
  test('declares its two rules', () {
    const check = SensitiveFilesCheck();

    expect(check.id, 'sensitive-files');
    expect(check.phase, CheckPhase.verify);
    expect(check.hasDynamicRules, isFalse);
    expect(
      [
        for (final rule in check.rules)
          (rule.id.toString(), rule.defaultSeverity),
      ],
      [
        ('sensitive-files/signing', Severity.error),
        ('sensitive-files/credentials', Severity.error),
      ],
    );
  });

  test('signing material by name and extension', () async {
    const paths = [
      'android/key.properties',
      'a/upload.jks',
      'b.keystore',
      'AuthKey_X.p8',
      'cert.p12',
      'c.pfx',
      'UPPER.JKS',
    ];

    final findings = await _run({for (final path in paths) path: 'x'});

    expect(findings, [
      for (final path in [...paths]..sort())
        _finding('signing', path, _signing),
    ]);
  });

  test('env files, except the documented examples', () async {
    final findings = await _run({
      '.env': 'A=1',
      '.env.production': 'A=1',
      'app/.env.local': 'A=1',
      '.env.example': 'A=',
      '.env.sample': 'A=',
      '.env.template': 'A=',
      'env.dart': '',
      '.envrc': '',
    });

    expect(findings, [
      _finding('credentials', '.env', _credentials),
      _finding('credentials', '.env.production', _credentials),
      _finding('credentials', 'app/.env.local', _credentials),
    ]);
  });

  test('a service account JSON is detected by its type field', () async {
    final findings = await _run({'firebase/sa.json': _serviceAccount});

    expect(findings, [
      _finding('credentials', 'firebase/sa.json', _credentials),
    ]);
  });

  test(
    'other JSON, JSON over 1 MiB and invalid JSON are not reported',
    () async {
      final pad = 'x' * (1024 * 1024);
      final big = '{"type": "service_account", "pad": "$pad"}';

      final findings = await _run({
        'other.json': '{"type": "user"}',
        'list.json': '[{"type": "service_account"}]',
        'big.json': big,
        'broken.json': '{"type": "service_account"',
      });

      expect(findings, isEmpty);
    },
  );

  test('no finding message ever contains file content', () async {
    final findings = await _run({
      'sa.json': _serviceAccount,
      '.env': 'SECRET=1',
      'key.properties': 'storePassword=SECRET',
    });

    expect(findings, hasLength(3));
    expect(findings.every((f) => !f.message.contains('SECRET')), isTrue);
  });

  test(
    'deleted files are not reported; renamed files are, at the new path',
    () async {
      final findings = await _run(
        {'secrets/upload.jks': 'x'},
        changes: [
          FileChange(path: RepoPath('old.jks'), kind: ChangeKind.deleted),
          FileChange(
            path: RepoPath('secrets/upload.jks'),
            kind: ChangeKind.renamed,
            previousPath: RepoPath('upload.jks'),
          ),
        ],
      );

      expect(findings, [_finding('signing', 'secrets/upload.jks', _signing)]);
    },
  );

  test('a symlink is judged by its path but never read as JSON', () async {
    final findings = await _run(
      {'link.jks': 'target', 'link.json': _serviceAccount},
      modes: {'link.jks': FileMode.symlink, 'link.json': FileMode.symlink},
    );

    expect(findings, [_finding('signing', 'link.jks', _signing)]);
  });

  test('a disabled rule is not reported', () async {
    final findings = await _run(
      {'.env': 'A=1', 'a.jks': 'x'},
      enabled: {const RuleId('sensitive-files', 'signing')},
    );

    expect(findings, [_finding('signing', 'a.jks', _signing)]);
  });
}

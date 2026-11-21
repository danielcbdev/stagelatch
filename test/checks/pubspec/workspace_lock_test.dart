import 'package:stagelatch/src/checks/pubspec/lockfile_document.dart';
import 'package:stagelatch/src/checks/pubspec/lockfile_out_of_sync.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_check.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_settings.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_snapshot_files.dart';

LocatedMap _root(String yaml, String path) {
  final result = const StructuredDocuments().parseYaml(yaml, RepoPath(path));
  return (result as DocumentParsed).root as LocatedMap;
}

String _locked(
  String name, {
  String version = '1.0.0',
  String source = 'hosted',
  String kind = 'direct main',
}) =>
    '  $name:\n'
    '    dependency: "$kind"\n'
    '    description:\n'
    '      name: $name\n'
    '    source: $source\n'
    '    version: "$version"\n';

String _lock(List<String> packages) =>
    'packages:\n${packages.join()}sdks:\n  dart: ">=3.0.0 <4.0.0"\n';

const _rootPkg = DartPackage(root: null, name: 'root');
final _a = DartPackage(root: RepoPath('packages/a'), name: 'a');
final _b = DartPackage(root: RepoPath('packages/b'), name: 'b');

PackageMap get _workspace => PackageMap(
  [_rootPkg, _a, _b],
  workspaceRoots: {_a: _rootPkg, _b: _rootPkg},
);

void main() {
  test(
    'lockfile-out-of-sync reads the root pubspec.lock for a member',
    () async {
      final context = FakeCheckContext(
        snapshot: FakeSnapshotFiles({
          'packages/a/pubspec.yaml': 'name: a\ndependencies:\n  http: ^1.2.0\n',
          'pubspec.lock': _lock([_locked('http', version: '0.13.6')]),
        }),
        changes: ChangeSet([
          FileChange(
            path: RepoPath('packages/a/pubspec.yaml'),
            kind: ChangeKind.modified,
          ),
        ]),
        packages: _workspace,
        settings: const [PubspecSettings()],
      );

      final findings = (await const PubspecCheck().run(context)).findings;

      expect(findings, hasLength(1));
      expect(findings.single.rule, lockfileOutOfSyncRule);
      expect(
        findings.single.message,
        'pubspec.lock does not satisfy "http": locked 0.13.6, required ^1.2.0.',
      );
    },
  );

  test(
    'a dependency that names another member is not missing from the lock',
    () {
      final findings = lockfileFindings(
        pubspec: PubspecDocument(
          _root(
            'name: a\ndependencies:\n  b: any\n  http: ^1.0.0\n',
            'packages/a/pubspec.yaml',
          ),
        ),
        lock: LockfileDocument(_root(_lock([_locked('http')]), 'pubspec.lock')),
        pubspecPath: RepoPath('packages/a/pubspec.yaml'),
        workspaceMemberNames: {'a', 'b', 'root'},
        checkDirectUndeclared: false,
      );

      expect(findings, isEmpty);
    },
  );

  test('a direct entry of the workspace lock is compared with the root '
      'pubspec only', () {
    final member = lockfileFindings(
      pubspec: PubspecDocument(
        _root(
          'name: a\ndependencies:\n  http: ^1.0.0\n',
          'packages/a/pubspec.yaml',
        ),
      ),
      lock: LockfileDocument(
        _root(_lock([_locked('http'), _locked('left_over')]), 'pubspec.lock'),
      ),
      pubspecPath: RepoPath('packages/a/pubspec.yaml'),
      workspaceMemberNames: {'a', 'b'},
      checkDirectUndeclared: false,
    );
    final root = lockfileFindings(
      pubspec: PubspecDocument(
        _root('name: root\ndependencies:\n  http: ^1.0.0\n', 'pubspec.yaml'),
      ),
      lock: LockfileDocument(
        _root(_lock([_locked('http'), _locked('left_over')]), 'pubspec.lock'),
      ),
      pubspecPath: RepoPath('pubspec.yaml'),
      workspaceMemberNames: {'a', 'b'},
    );

    expect(member, isEmpty);
    expect(root, hasLength(1));
    expect(
      root.single.message,
      'pubspec.lock lists "left_over" as a direct dependency, but '
      'pubspec.yaml does not declare it.',
    );
  });

  test('a changed root lock triggers the rule for every pubspec of the '
      'workspace', () async {
    final context = FakeCheckContext(
      snapshot: FakeSnapshotFiles({
        'pubspec.yaml': 'name: root\n',
        'packages/a/pubspec.yaml': 'name: a\ndependencies:\n  http: ^1.2.0\n',
        'packages/b/pubspec.yaml': 'name: b\ndependencies:\n  http: ^1.2.0\n',
        'pubspec.lock': _lock([_locked('http', version: '0.13.6')]),
      }),
      changes: ChangeSet([
        FileChange(path: RepoPath('pubspec.lock'), kind: ChangeKind.modified),
      ]),
      packages: _workspace,
      settings: const [PubspecSettings()],
    );

    final findings = (await const PubspecCheck().run(context)).findings;

    expect(findings.map((f) => f.location.path.value).toSet(), {
      'pubspec.yaml',
      'packages/a/pubspec.yaml',
      'packages/b/pubspec.yaml',
    });
  });
}

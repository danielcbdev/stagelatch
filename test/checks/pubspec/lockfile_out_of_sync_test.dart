import 'package:stagelatch/src/checks/pubspec/lockfile_document.dart';
import 'package:stagelatch/src/checks/pubspec/lockfile_out_of_sync.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

LocatedMap _root(String yaml, String path) {
  final result = const StructuredDocuments().parseYaml(yaml, RepoPath(path));
  return (result as DocumentParsed).root as LocatedMap;
}

/// One locked package in the format `pub` writes.
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

List<Finding> _findings(String pubspec, String lock) => lockfileFindings(
  pubspec: PubspecDocument(_root(pubspec, 'pubspec.yaml')),
  lock: LockfileDocument(_root(lock, 'pubspec.lock')),
  pubspecPath: RepoPath('pubspec.yaml'),
);

void main() {
  group('LockfileDocument', () {
    test('reads version, source and dependency kind of each package', () {
      final lock = LockfileDocument(
        _root(
          _lock([
            _locked('http', version: '0.13.6'),
            _locked('lints', kind: 'direct dev'),
            _locked('meta', kind: 'transitive'),
            _locked('flutter', source: 'sdk', version: '0.0.0'),
          ]),
          'pubspec.lock',
        ),
      );

      expect(lock.packages.keys, ['http', 'lints', 'meta', 'flutter']);
      expect(lock.packages['http']!.version, '0.13.6');
      expect(lock.packages['http']!.source, 'hosted');
      expect(lock.packages['http']!.dependencyKind, 'direct main');
      expect(lock.packages['lints']!.dependencyKind, 'direct dev');
      expect(lock.packages['flutter']!.source, 'sdk');
    });

    test('an entry without the expected fields is left out', () {
      final lock = LockfileDocument(
        _root(
          'packages:\n  odd: 3\n  half:\n    version: "1.0.0"\n'
              '${_locked('ok')}',
          'pubspec.lock',
        ),
      );

      expect(lock.packages.keys, ['ok']);
    });

    test('a lock without packages has none', () {
      final lock = LockfileDocument(
        _root('sdks:\n  dart: ">=3.0.0"\n', 'pubspec.lock'),
      );

      expect(lock.packages, isEmpty);
    });
  });

  group('lockfileFindings', () {
    test('lock does not satisfy a hosted constraint', () {
      final findings = _findings(
        'name: app\ndependencies:\n  http: ^1.2.0\n',
        _lock([_locked('http', version: '0.13.6')]),
      );

      expect(findings, hasLength(1));
      expect(findings.single.rule, lockfileOutOfSyncRule);
      expect(findings.single.severity, Severity.error);
      expect(
        findings.single.message,
        'pubspec.lock does not satisfy "http": locked 0.13.6, required '
        '^1.2.0.',
      );
      // The dependency's key in pubspec.yaml.
      expect(findings.single.location.path, RepoPath('pubspec.yaml'));
      expect(findings.single.location.start, const Position(3, 3));
    });

    test('a constraint written as a map with a version is checked too', () {
      final findings = _findings(
        'name: app\ndependencies:\n  http:\n    hosted: https://pub.dev\n'
        '    version: ^1.2.0\n',
        _lock([_locked('http', version: '0.13.6')]),
      );

      expect(findings.single.message, contains('required ^1.2.0'));
    });

    test('a satisfied constraint, "any" and an omitted constraint pass', () {
      expect(
        _findings(
          'name: app\ndependencies:\n  a: ^1.0.0\n  b: any\n  c:\n',
          _lock([_locked('a'), _locked('b'), _locked('c')]),
        ),
        isEmpty,
      );
    });

    test('a constraint that does not parse is skipped, not an error', () {
      expect(
        _findings(
          'name: app\ndependencies:\n  a: not-a-constraint\n',
          _lock([_locked('a')]),
        ),
        isEmpty,
      );
    });

    test('dependency missing from the lock', () {
      final findings = _findings(
        'name: app\ndependencies:\n  http: ^1.2.0\n',
        _lock([]),
      );

      expect(findings.single.message, '"http" is missing from pubspec.lock.');
      expect(findings.single.location.start, const Position(3, 3));
    });

    test('dev dependencies are checked like the others', () {
      final findings = _findings(
        'name: app\ndev_dependencies:\n  lints: ^3.0.0\n',
        _lock([_locked('lints', version: '2.0.0', kind: 'direct dev')]),
      );

      expect(findings.single.message, contains('"lints"'));
    });

    test('source kind differs', () {
      final findings = _findings(
        'name: app\ndependencies:\n  ui:\n    path: ../ui\n',
        _lock([_locked('ui')]),
      );

      expect(
        findings.single.message,
        'pubspec.lock resolves "ui" from hosted, but pubspec.yaml declares '
        'path.',
      );
      expect(findings.single.location.start, const Position(3, 3));
    });

    test('a git source in the lock for a hosted declaration differs', () {
      final findings = _findings(
        'name: app\ndependencies:\n  ui: ^1.0.0\n',
        _lock([_locked('ui', source: 'git')]),
      );

      expect(
        findings.single.message,
        'pubspec.lock resolves "ui" from git, but pubspec.yaml declares '
        'hosted.',
      );
    });

    test('git, path and sdk dependencies are compared by source only', () {
      expect(
        _findings(
          'name: app\ndependencies:\n  g:\n    git: https://example.com/g\n'
          '  p:\n    path: ../p\n  flutter:\n    sdk: flutter\n',
          _lock([
            _locked('g', source: 'git', version: '9.9.9'),
            _locked('p', source: 'path', version: '0.0.1'),
            _locked('flutter', source: 'sdk', version: '0.0.0'),
          ]),
        ),
        isEmpty,
      );
    });

    test('a direct lock entry the pubspec does not declare', () {
      final findings = _findings(
        'name: app\ndependencies:\n  http: ^1.0.0\n',
        _lock([_locked('http'), _locked('left_over')]),
      );

      expect(
        findings.single.message,
        'pubspec.lock lists "left_over" as a direct dependency, but '
        'pubspec.yaml does not declare it.',
      );
      expect(findings.single.location.path, RepoPath('pubspec.yaml'));
      expect(findings.single.location.start, const Position(1, 1));
    });

    test('transitive and overridden lock entries are not direct', () {
      expect(
        _findings(
          'name: app\ndependencies:\n  http: ^1.0.0\n',
          _lock([
            _locked('http'),
            _locked('meta', kind: 'transitive'),
            _locked('forced', kind: 'direct overridden'),
          ]),
        ),
        isEmpty,
      );
    });

    test('a dependency that is also overridden is not compared', () {
      expect(
        _findings(
          'name: app\ndependencies:\n  ui: ^1.0.0\n'
          'dependency_overrides:\n  ui:\n    path: ../ui\n',
          _lock([_locked('ui', source: 'path', kind: 'direct overridden')]),
        ),
        isEmpty,
      );
    });

    test('a clean pair yields nothing', () {
      expect(
        _findings(
          'name: app\ndependencies:\n  http: ^1.0.0\n'
          'dev_dependencies:\n  lints: ^3.0.0\n',
          _lock([
            _locked('http', version: '1.2.0'),
            _locked('lints', version: '3.0.0', kind: 'direct dev'),
          ]),
        ),
        isEmpty,
      );
    });
  });
}

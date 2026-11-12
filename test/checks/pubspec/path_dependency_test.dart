import 'package:stagelatch/src/checks/pubspec/path_dependency.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

PubspecDocument _document(String yaml, {String path = 'pubspec.yaml'}) {
  final result = const StructuredDocuments().parseYaml(yaml, RepoPath(path));
  return PubspecDocument((result as DocumentParsed).root as LocatedMap);
}

List<Finding> _findings(
  String yaml, {
  String path = 'pubspec.yaml',
  Set<String> pubspecs = const {},
}) => pathDependencyFindings(_document(yaml, path: path), RepoPath(path), {
  RepoPath(path),
  ...pubspecs.map(RepoPath.new),
});

void main() {
  group('targetPubspec', () {
    RepoPath? target(String from, String dependencyPath) =>
        targetPubspec(RepoPath(from), dependencyPath);

    test('resolves against the directory of the pubspec', () {
      expect(
        target('app/pubspec.yaml', '../packages/ui'),
        RepoPath('packages/ui/pubspec.yaml'),
      );
      expect(
        target('pubspec.yaml', 'packages/ui'),
        RepoPath('packages/ui/pubspec.yaml'),
      );
      expect(
        target('pubspec.yaml', './packages/./ui/'),
        RepoPath('packages/ui/pubspec.yaml'),
      );
    });

    test('a path that resolves to the repository root', () {
      expect(
        target('packages/ui/pubspec.yaml', '../..'),
        RepoPath('pubspec.yaml'),
      );
      expect(target('pubspec.yaml', '.'), RepoPath('pubspec.yaml'));
    });

    test('is null when the path climbs above the repository root', () {
      expect(target('pubspec.yaml', '../design_system'), isNull);
      expect(target('app/pubspec.yaml', '../../x'), isNull);
      expect(target('app/pubspec.yaml', 'a/../../../x'), isNull);
    });

    test('is null for absolute, drive and home paths', () {
      expect(target('pubspec.yaml', '/Users/dev/ui'), isNull);
      expect(target('pubspec.yaml', r'C:\src\ui'), isNull);
      expect(target('pubspec.yaml', 'c:/src/ui'), isNull);
      expect(target('pubspec.yaml', r'\\server\share\ui'), isNull);
      expect(target('pubspec.yaml', '~/src/ui'), isNull);
      expect(target('pubspec.yaml', ''), isNull);
    });

    test('accepts backslashes as separators', () {
      expect(
        target('app/pubspec.yaml', r'..\packages\ui'),
        RepoPath('packages/ui/pubspec.yaml'),
      );
    });
  });

  group('pathDependencyFindings', () {
    test('a path leaving the repository is reported at the path value', () {
      final findings = _findings(
        'name: app\n'
        'dependencies:\n'
        '  design_system:\n'
        '    path: ../design_system\n',
      );

      expect(findings, [
        Finding(
          rule: const RuleId('pubspec', 'path-dependency'),
          severity: Severity.error,
          message:
              'Dependency "design_system" uses a path that is not a package '
              'in this repository: ../design_system.',
          location: Location(
            RepoPath('pubspec.yaml'),
            const Position(4, 11),
            const Position(4, 27),
          ),
        ),
      ]);
    });

    test('a path to a package present in the snapshot is allowed', () {
      final findings = _findings(
        'name: app\ndependencies:\n  ui:\n    path: ../packages/ui\n',
        path: 'app/pubspec.yaml',
        pubspecs: {'packages/ui/pubspec.yaml'},
      );

      expect(findings, isEmpty);
    });

    test('a path inside the repository without a pubspec is reported', () {
      final findings = _findings(
        'name: app\ndependencies:\n  ui:\n    path: packages/ui\n',
      );

      expect(findings.single.message, endsWith('repository: packages/ui.'));
    });

    test('dev_dependencies are checked too', () {
      final findings = _findings(
        'name: app\ndev_dependencies:\n  tools:\n    path: ../tools\n',
      );

      expect(findings.single.message, startsWith('Dependency "tools" uses'));
    });

    test('dependency_overrides are left to their own rule', () {
      final findings = _findings(
        'name: app\ndependency_overrides:\n  ui:\n    path: ../ui\n',
      );

      expect(findings, isEmpty);
    });

    test('hosted, git and sdk dependencies are not path dependencies', () {
      final findings = _findings('''
name: app
dependencies:
  http: ^1.2.0
  flutter:
    sdk: flutter
  ui:
    git:
      url: https://example.com/ui.git
      path: packages/ui
  any_version:
''');

      expect(findings, isEmpty);
    });

    test('reports every offending dependency, in document order', () {
      final findings = _findings('''
name: app
dependencies:
  b:
    path: ../b
dev_dependencies:
  a:
    path: ../a
''');

      expect(findings.map((finding) => finding.location.start.line), [4, 7]);
    });

    test('odd shapes are ignored instead of failing', () {
      expect(_findings('name: app\ndependencies:\n'), isEmpty);
      expect(_findings('name: app\ndependencies: nope\n'), isEmpty);
      expect(_findings('name: app\ndependencies: [a, b]\n'), isEmpty);
      expect(
        _findings('name: app\ndependencies:\n  ui:\n    path:\n'),
        isEmpty,
      );
      expect(
        _findings('name: app\ndependencies:\n  ui:\n    path: [a]\n'),
        isEmpty,
      );
    });
  });
}

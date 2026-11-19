import 'package:stagelatch/src/checks/pubspec/dependency_overrides.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

List<Finding> _findings(String yaml, {String path = 'pubspec.yaml'}) {
  final result = const StructuredDocuments().parseYaml(yaml, RepoPath(path));
  final document = PubspecDocument(
    (result as DocumentParsed).root as LocatedMap,
  );
  return dependencyOverridesFindings(document, RepoPath(path));
}

void main() {
  test('non-empty overrides are reported at the key, names sorted', () {
    final findings = _findings(
      'name: app\n'
      'version: 1.0.0\n'
      'dependency_overrides:\n'
      '  intl: 0.19.0\n'
      '  http:\n'
      '    path: ../http\n',
    );

    expect(findings, [
      Finding(
        rule: const RuleId('pubspec', 'dependency-overrides'),
        severity: Severity.error,
        message: 'dependency_overrides must not be committed: http, intl.',
        location: Location(
          RepoPath('pubspec.yaml'),
          const Position(3, 1),
          const Position(3, 21),
        ),
      ),
    ]);
  });

  test('a single override is named alone', () {
    final findings = _findings('dependency_overrides:\n  intl: 0.19.0\n');

    expect(
      findings.single.message,
      'dependency_overrides must not be committed: intl.',
    );
  });

  test('the location carries the path of a nested pubspec', () {
    final findings = _findings(
      'dependency_overrides:\n  intl: 0.19.0\n',
      path: 'packages/ui/pubspec.yaml',
    );

    expect(findings.single.location.path, RepoPath('packages/ui/pubspec.yaml'));
  });

  test('missing, empty or null overrides are not reported', () {
    expect(_findings('name: app\n'), isEmpty);
    expect(_findings('name: app\ndependency_overrides:\n'), isEmpty);
    expect(_findings('name: app\ndependency_overrides: {}\n'), isEmpty);
  });

  test('overrides that are not a map are ignored instead of failing', () {
    expect(_findings('name: app\ndependency_overrides: nope\n'), isEmpty);
    expect(_findings('name: app\ndependency_overrides: [a]\n'), isEmpty);
  });
}

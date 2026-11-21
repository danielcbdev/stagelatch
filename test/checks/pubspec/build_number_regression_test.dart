import 'package:stagelatch/src/checks/pubspec/build_number_regression.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

PubspecDocument _document(String yaml) {
  final result = const StructuredDocuments().parseYaml(
    yaml,
    RepoPath('pubspec.yaml'),
  );
  return PubspecDocument((result as DocumentParsed).root as LocatedMap);
}

String _pubspec(String? version) =>
    'name: app\n${version == null ? '' : 'version: $version\n'}';

/// The findings for a version that goes from [base] to [snapshot].
List<Finding> _regress(String? base, String? snapshot) =>
    buildNumberRegressionFindings(
      snapshot: _document(_pubspec(snapshot)),
      base: _document(_pubspec(base)),
      path: RepoPath('pubspec.yaml'),
    );

void main() {
  test('version going backwards', () {
    final findings = _regress('1.2.0+10', '1.1.9+11');

    expect(findings, hasLength(1));
    expect(findings.single.rule, buildNumberRegressionRule);
    expect(findings.single.severity, Severity.error);
    expect(
      findings.single.message,
      'Version went backwards: 1.2.0+10 -> 1.1.9+11.',
    );
    // The `version` value.
    expect(findings.single.location.start, const Position(2, 10));
  });

  test('the build number going backwards, or disappearing', () {
    expect(_regress('1.2.0+10', '1.2.0+9'), hasLength(1));
    expect(
      _regress('1.2.0+10', '1.2.0').single.message,
      'Version went backwards: 1.2.0+10 -> 1.2.0.',
    );
  });

  test('build numbers are compared as numbers, not as text', () {
    expect(_regress('1.2.0+9', '1.2.0+10'), isEmpty);
    expect(_regress('1.2.0+10', '1.2.0+9'), hasLength(1));
  });

  test('equal or growing versions are accepted', () {
    expect(_regress('1.2.0+10', '1.2.0+10'), isEmpty);
    expect(_regress('1.2.0+10', '1.3.0+1'), isEmpty);
    expect(_regress('1.2.0', '1.2.0+1'), isEmpty);
    expect(_regress('1.2.0', '1.2.1'), isEmpty);
  });

  test('a pre-release is lower than its release', () {
    expect(_regress('1.2.0', '1.2.0-rc.1'), hasLength(1));
    expect(_regress('1.2.0-rc.1', '1.2.0'), isEmpty);
  });

  test('non-numeric build segments are compared as text', () {
    expect(_regress('1.2.0+b', '1.2.0+a'), hasLength(1));
    expect(_regress('1.2.0+a', '1.2.0+b'), isEmpty);
  });

  test('no base, or no version in either file, is not a regression', () {
    final snapshot = _document(_pubspec('1.2.0+1'));
    final path = RepoPath('pubspec.yaml');

    expect(
      buildNumberRegressionFindings(snapshot: snapshot, base: null, path: path),
      isEmpty,
    );
    expect(_regress(null, '1.2.0+1'), isEmpty);
    expect(_regress('1.2.0+1', null), isEmpty);
  });

  test('a version that does not parse is ignored', () {
    expect(_regress('1.2.0+10', 'not-a-version'), isEmpty);
    expect(_regress('not-a-version', '1.2.0+10'), isEmpty);
    expect(_regress('1.2.0+10', '1'), isEmpty);
  });
}

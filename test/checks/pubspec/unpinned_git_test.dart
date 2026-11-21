import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/checks/pubspec/unpinned_git.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

const _sha = '0123456789abcdef0123456789abcdef01234567';

List<Finding> _findings(String yaml, {bool requireSha = false}) {
  final path = RepoPath('pubspec.yaml');
  final result = const StructuredDocuments().parseYaml(yaml, path);
  final document = PubspecDocument(
    (result as DocumentParsed).root as LocatedMap,
  );
  return unpinnedGitFindings(document, path, requireSha: requireSha);
}

void main() {
  test('git dependency without ref', () {
    final findings = _findings('''
name: app
dependencies:
  ui:
    git:
      url: https://example.com/ui.git
''');

    expect(findings, hasLength(1));
    expect(findings.single.rule, unpinnedGitRule);
    expect(findings.single.severity, Severity.error);
    expect(findings.single.message, 'Git dependency "ui" has no ref.');
    // The `git` key.
    expect(findings.single.location.start, const Position(4, 5));
  });

  test('short form (git: url) has no ref', () {
    final findings = _findings('''
name: app
dev_dependencies:
  ui:
    git: https://example.com/ui.git
''');

    expect(findings.single.message, 'Git dependency "ui" has no ref.');
    expect(findings.single.location.start, const Position(4, 5));
  });

  test('a git dependency with a ref is accepted without require_sha', () {
    expect(
      _findings('''
name: app
dependencies:
  ui:
    git:
      url: https://example.com/ui.git
      ref: main
'''),
      isEmpty,
    );
  });

  test('require_sha rejects branch and tag refs and accepts 40 hex '
      'characters', () {
    String yaml(String ref) =>
        'name: app\ndependencies:\n  ui:\n    git:\n'
        '      url: https://example.com/ui.git\n      ref: $ref\n';

    final main = _findings(yaml('main'), requireSha: true);
    expect(
      main.single.message,
      'Git dependency "ui" must be pinned to a full commit SHA, found '
      '"main".',
    );
    // The `ref` value.
    expect(main.single.location.start, const Position(6, 12));

    expect(_findings(yaml(_sha), requireSha: true), isEmpty);
    expect(_findings(yaml(_sha.toUpperCase()), requireSha: true), isEmpty);
    expect(
      _findings(yaml(_sha.substring(1)), requireSha: true),
      hasLength(1),
      reason: 'a short SHA is not a full commit id',
    );
    expect(
      _findings(yaml('${_sha}0'), requireSha: true),
      hasLength(1),
      reason: 'a 41-character value is not a commit id',
    );
  });

  test('require_sha still reports a missing ref once, as "no ref"', () {
    final findings = _findings('''
name: app
dependencies:
  ui:
    git:
      url: https://example.com/ui.git
''', requireSha: true);

    expect(findings.single.message, 'Git dependency "ui" has no ref.');
  });

  test('hosted, path and sdk dependencies are not git dependencies', () {
    expect(
      _findings('''
name: app
dependencies:
  http: ^1.2.0
  local:
    path: ../local
  flutter:
    sdk: flutter
'''),
      isEmpty,
    );
  });

  test('dependency_overrides are left to their own rule', () {
    expect(
      _findings('''
name: app
dependency_overrides:
  ui:
    git: https://example.com/ui.git
'''),
      isEmpty,
    );
  });

  test('an empty ref counts as no ref', () {
    final findings = _findings('''
name: app
dependencies:
  ui:
    git:
      url: https://example.com/ui.git
      ref:
''');

    expect(findings.single.message, 'Git dependency "ui" has no ref.');
  });

  test('findings follow document order', () {
    final findings = _findings('''
name: app
dependencies:
  b:
    git: https://example.com/b.git
  a:
    git: https://example.com/a.git
''');

    expect(findings.map((f) => f.message), [
      'Git dependency "b" has no ref.',
      'Git dependency "a" has no ref.',
    ]);
  });
}

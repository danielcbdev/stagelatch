import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/inline_ignore.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_check.dart';
import '../../support/fake_snapshot_files.dart';

void main() {
  group('scanIgnores', () {
    test('a directive covers its own line and the next', () {
      final d = scanIgnores(
        'a\n// stagelatch:ignore tests/solo\nb\n',
        commentOpener: '//',
      ).single;

      expect(d.line, 2);
      expect(d.ids.single.text, 'tests/solo');
      expect(d.ids.single.column, 22);
    });

    test('several ids, spaces around commas, and trailing free text', () {
      final ids = scanIgnores(
        'x(); // stagelatch:ignore a/b , c/d flaky, see #42',
        commentOpener: '//',
      ).single.ids;

      expect(ids.map((i) => i.text), ['a/b', 'c/d']);
      expect(ids.map((i) => i.column), [27, 33]);
    });

    test('the marker must directly follow the comment opener', () {
      expect(
        scanIgnores('// see stagelatch:ignore a/b', commentOpener: '//'),
        isEmpty,
      );
      expect(
        scanIgnores('//stagelatch:ignore a/b', commentOpener: '//'),
        hasLength(1),
      );
    });

    test('a longer word that starts with the marker is not the marker', () {
      expect(
        scanIgnores('// stagelatch:ignored a/b', commentOpener: '//'),
        isEmpty,
      );
    });

    test('a doc comment carries the marker too', () {
      expect(
        scanIgnores(
          '/// stagelatch:ignore a/b',
          commentOpener: '//',
        ).single.ids.single.column,
        23,
      );
    });

    test('YAML uses #', () {
      final d = scanIgnores(
        'dependency_overrides: # stagelatch:ignore pubspec/dependency-overrides',
        commentOpener: '#',
      ).single;

      expect(d.line, 1);
      expect(d.ids.single.text, 'pubspec/dependency-overrides');
    });

    test('a comment with no id is no directive', () {
      expect(scanIgnores('// stagelatch:ignore', commentOpener: '//'), isEmpty);
      expect(
        scanIgnores('// stagelatch:ignore   ', commentOpener: '//'),
        isEmpty,
      );
    });

    test('CRLF line endings do not reach the ids', () {
      final d = scanIgnores(
        'a\r\n// stagelatch:ignore a/b\r\n',
        commentOpener: '//',
      ).single;

      expect(d.line, 2);
      expect(d.ids.single.text, 'a/b');
    });

    test('a one-megabyte line is scanned in linear time', () {
      final hostile = '/' * (1024 * 1024);
      final spaces = '// ${' ' * (1024 * 1024)}';

      expect(scanIgnores(hostile, commentOpener: '//'), isEmpty);
      expect(scanIgnores(spaces, commentOpener: '//'), isEmpty);
    });
  });

  group('commentOpenerFor', () {
    test('Dart files use //, YAML files use #', () {
      expect(commentOpenerFor(RepoPath('lib/a.dart')), '//');
      expect(commentOpenerFor(RepoPath('pubspec.yaml')), '#');
      expect(commentOpenerFor(RepoPath('a/b.yml')), '#');
    });

    test('files without a comment form have no inline ignore', () {
      expect(commentOpenerFor(RepoPath('lib/l10n/app_en.arb')), isNull);
      expect(commentOpenerFor(RepoPath('data.json')), isNull);
    });
  });

  group('applyInlineIgnores', () {
    final pubspec = FakeCheck('pubspec', rules: ['dependency-overrides']);
    final tests = FakeCheck('tests', rules: ['solo']);
    final analyze = FakeCheck('analyze', rules: [], hasDynamicRules: true);
    final catalog = CheckRegistry([pubspec, tests, analyze]);

    ChangeSet changed(List<String> paths) => ChangeSet([
      for (final path in paths)
        FileChange(path: RepoPath(path), kind: ChangeKind.modified),
    ]);

    test('a finding on line n or n+1 with a named rule is suppressed; '
        'others are kept', () async {
      const text =
          'a\n'
          '// stagelatch:ignore tests/solo\n'
          'b\n'
          'c\n';
      final onComment = tests.finding('t.dart', rule: 'solo', line: 2);
      final below = tests.finding('t.dart', rule: 'solo', line: 3);
      final twoBelow = tests.finding('t.dart', rule: 'solo', line: 4);
      final above = tests.finding('t.dart', rule: 'solo');
      final otherRule = pubspec.finding(
        't.dart',
        rule: 'dependency-overrides',
        line: 3,
      );

      final outcome = await applyInlineIgnores(
        [onComment, below, twoBelow, above, otherRule],
        snapshot: FakeSnapshotFiles({'t.dart': text}),
        changes: changed(['t.dart']),
        catalog: catalog,
      );

      expect(outcome.kept, [twoBelow, above, otherRule]);
      expect(outcome.suppressed, 2);
      expect(outcome.invalid, isEmpty);
    });

    test('a file without a comment form keeps its findings', () async {
      final finding = tests.finding('a.json', rule: 'solo');

      final outcome = await applyInlineIgnores(
        [finding],
        snapshot: FakeSnapshotFiles({
          'a.json': '// stagelatch:ignore tests/solo\n',
        }),
        changes: changed(['a.json']),
        catalog: catalog,
      );

      expect(outcome.kept, [finding]);
      expect(outcome.suppressed, 0);
    });

    test('an unknown id yields stagelatch/invalid-ignore at the id, '
        'in changed files only', () async {
      const text = 'x: 1 # stagelatch:ignore pubspec/nope\n';

      final outcome = await applyInlineIgnores(
        const [],
        snapshot: FakeSnapshotFiles({'pubspec.yaml': text, 'other.yaml': text}),
        changes: changed(['pubspec.yaml']),
        catalog: catalog,
      );

      expect(outcome.invalid, [
        Finding(
          rule: invalidIgnoreRule,
          severity: Severity.warning,
          message: 'Unknown rule "pubspec/nope" in stagelatch:ignore.',
          location: Location(
            RepoPath('pubspec.yaml'),
            const Position(1, 26),
            const Position(1, 38),
          ),
        ),
      ]);
    });

    test('a deleted file is not scanned for invalid ids', () async {
      final outcome = await applyInlineIgnores(
        const [],
        snapshot: FakeSnapshotFiles(const {}),
        changes: ChangeSet([
          FileChange(path: RepoPath('gone.dart'), kind: ChangeKind.deleted),
        ]),
        catalog: catalog,
      );

      expect(outcome.invalid, isEmpty);
    });

    test('ids under analyze/ are always accepted', () async {
      final outcome = await applyInlineIgnores(
        const [],
        snapshot: FakeSnapshotFiles({
          'a.dart': '// stagelatch:ignore analyze/anything_at_all\n',
        }),
        changes: changed(['a.dart']),
        catalog: CheckRegistry([pubspec]),
      );

      expect(outcome.invalid, isEmpty);
    });

    test(
      'stagelatch/invalid-ignore is a known id but suppresses nothing',
      () async {
        const text = '// stagelatch:ignore stagelatch/invalid-ignore, x/y\n';

        final outcome = await applyInlineIgnores(
          const [],
          snapshot: FakeSnapshotFiles({'a.dart': text}),
          changes: changed(['a.dart']),
          catalog: catalog,
        );

        expect(outcome.invalid.map((f) => f.message), [
          'Unknown rule "x/y" in stagelatch:ignore.',
        ]);
      },
    );
  });

  test('the registry knows stagelatch/invalid-ignore', () {
    expect(CheckRegistry(const []).hasRule(invalidIgnoreRule), isTrue);
    expect(invalidIgnoreRule, const RuleId('stagelatch', 'invalid-ignore'));
  });
}

import 'package:stagelatch/src/checks/tests/tests_check.dart';
import 'package:stagelatch/src/checks/tests/tests_rules.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_dart_toolchain.dart';
import '../../support/fake_snapshot_files.dart';

/// A test file whose `main` holds [body].
String _file(String body) => 'void main() {\n$body\n}\n';

/// Runs the check. Every path of [files] is changed unless [changed] says
/// otherwise; [renamed] maps a new path to its path in [base].
Future<List<Finding>> _run(
  Map<String, Object> files, {
  Map<String, Object>? base,
  List<String>? changed,
  Map<String, String> renamed = const {},
  List<String> deleted = const [],
  Set<RuleId>? enabled,
}) async {
  final context = FakeCheckContext(
    snapshot: FakeSnapshotFiles(files),
    base: base == null ? null : FakeSnapshotFiles(base),
    changes: ChangeSet([
      for (final path in changed ?? files.keys)
        if (renamed.containsKey(path))
          FileChange(
            path: RepoPath(path),
            kind: ChangeKind.renamed,
            previousPath: RepoPath(renamed[path]!),
          )
        else
          FileChange(
            path: RepoPath(path),
            kind: base == null || base.containsKey(path)
                ? ChangeKind.modified
                : ChangeKind.added,
          ),
      for (final path in deleted)
        FileChange(path: RepoPath(path), kind: ChangeKind.deleted),
    ]),
    packages: PackageMap([const DartPackage(root: null, name: 'app')]),
    dart: FakeDartToolchain(),
    enabled: enabled,
  );
  final result = await const TestsCheck().run(context);
  expect(result.fixes, isEmpty);
  return result.findings;
}

void main() {
  group('TestsCheck', () {
    test('declares its identity and rules', () {
      const check = TestsCheck();

      expect(check.id, 'tests');
      expect(check.phase, CheckPhase.verify);
      expect(check.hasDynamicRules, isFalse);
      expect(check.rules.map((rule) => rule.id.toString()), [
        'tests/solo',
        'tests/new-skip',
        'tests/affected',
      ]);
      expect(check.rules.first.defaultSeverity, Severity.error);
      expect(check.rules[1].defaultSeverity, Severity.warning);
      expect(check.rules.last.defaultSeverity, Severity.error);
      expect(check.rules.every((rule) => rule.summary.endsWith('.')), isTrue);
    });

    group('solo', () {
      test('is reported at the argument', () async {
        final findings = await _run({
          'test/a_test.dart': _file("  test('a', () {}, solo: true);"),
        });

        expect(findings, hasLength(1));
        expect(findings.single.rule, soloRule);
        expect(findings.single.severity, Severity.error);
        expect(
          findings.single.message,
          '"solo" must not be committed: it silently skips every other test.',
        );
        expect(findings.single.location.path, RepoPath('test/a_test.dart'));
        expect(findings.single.location.start, const Position(2, 20));
        expect(findings.single.location.end, const Position(2, 30));
      });

      test('solo: false is not reported; a variable is', () async {
        final findings = await _run({
          'test/a_test.dart': _file(
            "  test('a', () {}, solo: false);\n"
            "  test('b', () {}, solo: flag);",
          ),
        });

        expect(findings, hasLength(1));
        expect(findings.single.location.start.line, 3);
      });

      test('every solo of a file is reported, groups included', () async {
        final findings = await _run({
          'test/a_test.dart': _file(
            "  group('g', () { test('a', () {}, solo: true); }, solo: true);",
          ),
        });

        expect(findings, hasLength(2));
      });

      test('a file that did not change, or is not a test file, is not '
          'examined', () async {
        final findings = await _run(
          {
            'test/a_test.dart': _file("  test('a', () {}, solo: true);"),
            'lib/b.dart': _file("  test('a', () {}, solo: true);"),
            'test/helper.dart': _file("  test('a', () {}, solo: true);"),
          },
          changed: ['lib/b.dart', 'test/helper.dart'],
        );

        expect(findings, isEmpty);
      });
    });

    group('new-skip', () {
      test('a skip added to an existing test is a warning', () async {
        final findings = await _run(
          {'test/a_test.dart': _file("  test('adds', () {}, skip: true);")},
          base: {'test/a_test.dart': _file("  test('adds', () {});")},
        );

        expect(findings, hasLength(1));
        expect(findings.single.rule, newSkipRule);
        expect(findings.single.severity, Severity.warning);
        expect(
          findings.single.message,
          'Test "adds" was skipped in this change.',
        );
        expect(findings.single.location.start, const Position(2, 23));
        expect(findings.single.location.end, const Position(2, 33));
      });

      test('a skip that exists in the base is not reported', () async {
        final findings = await _run(
          {'test/a_test.dart': _file("  test('adds', () {}, skip: 'wip');")},
          base: {
            'test/a_test.dart': _file("  test('adds', () {}, skip: true);"),
          },
        );

        expect(findings, isEmpty);
      });

      test('a new test that is born skipped is reported', () async {
        final findings = await _run(
          {
            'test/a_test.dart': _file(
              "  test('old', () {});\n  test('new', () {}, skip: true);",
            ),
          },
          base: {'test/a_test.dart': _file("  test('old', () {});")},
        );

        expect(
          findings.single.message,
          'Test "new" was skipped in this change.',
        );
      });

      test('two tests with the same key: only the additional skip is '
          'reported', () async {
        final findings = await _run(
          {
            'test/a_test.dart': _file(
              "  test('dup', () {}, skip: true);\n"
              "  test('dup', () {}, skip: true);",
            ),
          },
          base: {
            'test/a_test.dart': _file(
              "  test('dup', () {}, skip: true);\n  test('dup', () {});",
            ),
          },
        );

        expect(findings, hasLength(1));
        // The later one, in source order.
        expect(findings.single.location.start.line, 3);
      });

      test('the key includes the groups', () async {
        final findings = await _run(
          {
            'test/a_test.dart': _file(
              "  group('b', () { test('x', () {}, skip: true); });",
            ),
          },
          base: {
            'test/a_test.dart': _file(
              "  group('a', () { test('x', () {}, skip: true); });",
            ),
          },
        );

        expect(findings.single.message, 'Test "x" was skipped in this change.');
      });

      test('a skipped group is reported by its own description', () async {
        final findings = await _run(
          {
            'test/a_test.dart': _file(
              "  group('slow', () { test('x', () {}); }, skip: true);",
            ),
          },
          base: {
            'test/a_test.dart': _file(
              "  group('slow', () { test('x', () {}); });",
            ),
          },
        );

        expect(
          findings.single.message,
          'Test "slow" was skipped in this change.',
        );
      });

      test('a description built from a variable falls back to its source '
          'text', () async {
        const source =
            '  test(name, () {}, skip: true);\n'
            r"  test('a $n', () {}, skip: true);";
        final unchanged = await _run(
          {'test/a_test.dart': _file(source)},
          base: {'test/a_test.dart': _file(source)},
        );
        final added = await _run(
          {'test/a_test.dart': _file(source)},
          base: {
            'test/a_test.dart': _file(
              "  test(name, () {});\n  test('a \$n', () {}, skip: true);",
            ),
          },
        );

        expect(unchanged, isEmpty);
        expect(added.single.message, 'Test "name" was skipped in this change.');
      });

      test('a new file has no base: every skip is new', () async {
        final source = _file(
          "  test('a', () {}, skip: true);\n  test('b', () {}, skip: true);",
        );
        final noBase = await _run({'test/a_test.dart': source});
        final absent = await _run(
          {'test/a_test.dart': source},
          base: {'test/other_test.dart': ''},
        );

        expect(noBase, hasLength(2));
        expect(absent, hasLength(2));
      });

      test('a @Skip annotation on the library skips every test of the '
          'file', () async {
        const tests = "  test('a', () {});\n  test('b', () {});";
        final findings = await _run(
          {'test/a_test.dart': "@Skip('later')\nlibrary;\n\n${_file(tests)}"},
          base: {'test/a_test.dart': _file(tests)},
        );

        expect(findings.map((f) => f.message), [
          'Test "a" was skipped in this change.',
          'Test "b" was skipped in this change.',
        ]);
        expect(findings.first.location.start, const Position(1, 1));
      });

      test('a renamed test file is compared with its previous path', () async {
        final unchanged = await _run(
          {'test/new_test.dart': _file("  test('a', () {}, skip: true);")},
          base: {
            'test/old_test.dart': _file("  test('a', () {}, skip: true);"),
          },
          renamed: {'test/new_test.dart': 'test/old_test.dart'},
        );
        final added = await _run(
          {'test/new_test.dart': _file("  test('a', () {}, skip: true);")},
          base: {'test/old_test.dart': _file("  test('a', () {});")},
          renamed: {'test/new_test.dart': 'test/old_test.dart'},
        );

        expect(unchanged, isEmpty);
        expect(added, hasLength(1));
      });

      test('a file that did not change is not examined', () async {
        final findings = await _run(
          {
            'test/a_test.dart': _file("  test('a', () {}, skip: true);"),
            'lib/x.dart': '',
          },
          base: {'test/a_test.dart': _file("  test('a', () {});")},
          changed: ['lib/x.dart'],
        );

        expect(findings, isEmpty);
      });

      test('a deleted test file is not examined', () async {
        final findings = await _run(
          {'lib/x.dart': ''},
          base: {'test/a_test.dart': _file("  test('a', () {});")},
          changed: ['lib/x.dart'],
          deleted: ['test/a_test.dart'],
        );

        expect(findings, isEmpty);
      });
    });

    test('a file the lexer cannot read is left to analyze', () async {
      final findings = await _run({
        'test/a_test.dart':
            "void main() {\n  test('a', () {}, solo: true, skip: 'oops);\n",
      });

      expect(findings, isEmpty);
    });

    test('a base that cannot be read makes every skip new', () async {
      final findings = await _run(
        {'test/a_test.dart': _file("  test('a', () {}, skip: true);")},
        base: {'test/a_test.dart': "void main() { 'oops;"},
      );

      expect(findings, hasLength(1));
    });

    test('a disabled rule produces nothing', () async {
      final files = {
        'test/a_test.dart': _file(
          "  test('a', () {}, solo: true, skip: true);",
        ),
      };

      Future<List<RuleId>> only(RuleId rule) async => [
        for (final finding in await _run(files, enabled: {rule})) finding.rule,
      ];

      expect(await only(soloRule), [soloRule]);
      expect(await only(newSkipRule), [newSkipRule]);
    });

    test('solo and skip of one call are reported separately', () async {
      final findings = await _run({
        'test/a_test.dart': _file(
          "  test('a', () {}, solo: true, skip: true);",
        ),
      });

      expect(findings.map((f) => f.rule), [soloRule, newSkipRule]);
      expect(findings.map((f) => f.location.start.column), [20, 32]);
    });
  });
}

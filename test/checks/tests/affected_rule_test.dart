import 'package:stagelatch/src/checks/tests/affected_rule.dart';
import 'package:stagelatch/src/checks/tests/affected_tests.dart';
import 'package:stagelatch/src/checks/tests/tests_rules.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/dart/import_graph.dart';
import 'package:stagelatch/src/domain/dart/test_runner.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_snapshot_files.dart';
import '../../support/fake_test_runner.dart';

const _app = DartPackage(root: null, name: 'app');
final _ui = DartPackage(root: RepoPath('packages/ui'), name: 'ui');

RepoPath path(String value) => RepoPath(value);

const _skip =
    'Affected tests were not run: 2 file(s) they execute differ from the '
    'working tree (uncommitted changes, untracked files, or another '
    'checked-out commit).';

/// A [FakeCheckContext] over [files] (path to the URIs it imports; the
/// import of a path that is not a key is an edge to a file the snapshot
/// lacks) with [changes] written as `M path`, `A path` or `D path`.
FakeCheckContext _context(
  Map<String, List<String>> files,
  List<String> changes, {
  FakeTestRunner? runner,
  EntryKind entry = EntryKind.prePush,
  List<DartPackage> packages = const [_app],
  Set<String> dirty = const {},
  List<Set<String>>? answers,
  Set<String> extraSnapshot = const {},
  bool enabled = true,
}) {
  final map = PackageMap(packages);
  return FakeCheckContext(
    entry: entry,
    changes: ChangeSet([
      for (final change in changes)
        FileChange(
          path: path(change.substring(2)),
          kind: switch (change[0]) {
            'M' => ChangeKind.modified,
            'A' => ChangeKind.added,
            _ => ChangeKind.deleted,
          },
        ),
    ]),
    snapshot: FakeSnapshotFiles({
      for (final key in [...files.keys, ...extraSnapshot]) key: '',
    }),
    packages: map,
    importGraph: ImportGraph.build(
      directives: {
        for (final MapEntry(:key, :value) in files.entries)
          path(key): [
            for (final (index, uri) in value.indexed)
              Directive(
                kind: DirectiveKind.import,
                uri: uri,
                location: Location(
                  path(key),
                  Position(index + 1, 8),
                  Position(index + 1, 8 + uri.length),
                ),
              ),
          ],
      },
      packages: map,
    ),
    tests: runner ?? FakeTestRunner(),
    dirty: {for (final value in dirty) path(value)},
    divergentAnswers: [
      for (final answer in answers ?? const <Set<String>>[])
        {for (final value in answer) path(value)},
    ],
    enabled: enabled ? null : const <RuleId>{},
  );
}

Future<List<Finding>> _run(FakeCheckContext context) =>
    affectedFindings(context);

void main() {
  group('when nothing runs', () {
    test('no affected test: no divergence check, no run, no finding', () async {
      final runner = FakeTestRunner();
      final context = _context(
        {
          'lib/a.dart': [],
          'lib/b.dart': [],
          'test/b_test.dart': ['../lib/b.dart'],
        },
        ['M lib/a.dart'],
        runner: runner,
        dirty: {'lib/a.dart'},
      );

      expect(await _run(context), isEmpty);
      expect(runner.calls, isEmpty);
      expect(context.divergentCalls, isEmpty);
    });

    test(
      'a change that is not Dart or package configuration is ignored',
      () async {
        final runner = FakeTestRunner();
        final context = _context(
          {'test/a_test.dart': []},
          ['M README.md', 'M assets/logo.png'],
          runner: runner,
        );

        expect(await _run(context), isEmpty);
        expect(runner.calls, isEmpty);
        expect(context.divergentCalls, isEmpty);
      },
    );

    test('on pre-commit nothing runs even when tests are affected', () async {
      final runner = FakeTestRunner();
      final context = _context(
        {'test/a_test.dart': []},
        ['M test/a_test.dart'],
        runner: runner,
        entry: EntryKind.preCommit,
      );

      expect(await _run(context), isEmpty);
      expect(runner.calls, isEmpty);
      expect(context.divergentCalls, isEmpty);
    });

    test('a rule that is not enabled does nothing', () async {
      final runner = FakeTestRunner();
      final context = _context(
        {'test/a_test.dart': []},
        ['M test/a_test.dart'],
        runner: runner,
        enabled: false,
      );

      expect(await _run(context), isEmpty);
      expect(runner.calls, isEmpty);
      expect(context.divergentCalls, isEmpty);
    });

    test('a deleted Dart file with no importer left selects nothing', () async {
      final context = _context({'test/a_test.dart': []}, ['D lib/gone.dart']);

      expect(await _run(context), isEmpty);
      expect(context.divergentCalls, isEmpty);
    });
  });

  group('findings of a run', () {
    test('one finding per failed test at its declaration', () async {
      final runner = FakeTestRunner(
        fallback: TestRunResult(
          failures: [
            FailedTest(
              file: path('test/cart_test.dart'),
              line: 12,
              column: 3,
              name: 'cart adds an item',
            ),
          ],
        ),
      );
      final findings = await _run(
        _context(
          {'test/cart_test.dart': []},
          ['M test/cart_test.dart'],
          runner: runner,
        ),
      );

      final finding = findings.single;
      expect(finding.rule, affectedRule);
      expect(finding.message, 'Test failed: cart adds an item.');
      expect(
        finding.location,
        Location(
          path('test/cart_test.dart'),
          const Position(12, 3),
          const Position(12, 3),
        ),
      );
      expect(finding.severity, Severity.error);
      expect(finding.severityLocked, isFalse);
    });

    test('a startup error is one finding at the first affected file of the '
        'package', () async {
      final runner = FakeTestRunner(
        fallback: const TestRunResult(startupError: 'compile error'),
      );
      final findings = await _run(
        _context(
          {'test/a_test.dart': [], 'test/b_test.dart': []},
          ['M test/b_test.dart', 'M test/a_test.dart'],
          runner: runner,
        ),
      );

      expect(findings.single.message, 'Tests could not be run: compile error.');
      expect(
        findings.single.location,
        Location.wholeFile(path('test/a_test.dart')),
      );
      expect(findings.single.severity, Severity.error);
    });

    test('a run with a failure and a startup error in different packages '
        'reports both', () async {
      final runner = FakeTestRunner(
        results: {
          'app': TestRunResult(
            failures: [
              FailedTest(
                file: path('test/a_test.dart'),
                line: 2,
                column: 1,
                name: 'a fails',
              ),
            ],
          ),
          'ui': const TestRunResult(startupError: 'no pubspec.lock'),
        },
      );
      final findings = await _run(
        _context(
          {'test/a_test.dart': [], 'packages/ui/test/u_test.dart': []},
          ['M test/a_test.dart', 'M packages/ui/test/u_test.dart'],
          runner: runner,
          packages: [_app, _ui],
        ),
      );

      expect(findings.map((f) => f.message), [
        'Test failed: a fails.',
        'Tests could not be run: no pubspec.lock.',
      ]);
      expect(
        findings.last.location,
        Location.wholeFile(path('packages/ui/test/u_test.dart')),
      );
    });

    test(
      'each package is run once, in path order, with its own files',
      () async {
        final runner = FakeTestRunner();
        await _run(
          _context(
            {
              'test/a_test.dart': [],
              'test/b_test.dart': [],
              'packages/ui/test/u_test.dart': [],
            },
            [
              'M packages/ui/test/u_test.dart',
              'M test/b_test.dart',
              'M test/a_test.dart',
            ],
            runner: runner,
            packages: [_ui, _app],
          ),
        );

        expect(
          [for (final call in runner.calls) call.package.name],
          ['app', 'ui'],
        );
        expect(runner.calls[0].files, [
          path('test/a_test.dart'),
          path('test/b_test.dart'),
        ]);
        expect(runner.calls[1].files, [path('packages/ui/test/u_test.dart')]);
      },
    );

    test('a changed pubspec.yaml runs every test of its package', () async {
      final runner = FakeTestRunner();
      await _run(
        _context(
          {
            'test/a_test.dart': [],
            'test/b_test.dart': [],
            'packages/ui/test/u_test.dart': [],
          },
          ['M packages/ui/pubspec.yaml'],
          runner: runner,
          packages: [_app, _ui],
        ),
      );

      expect(runner.calls.single.package.name, 'ui');
      expect(runner.calls.single.files, [path('packages/ui/test/u_test.dart')]);
    });

    test('a change in a dependency of a test selects it', () async {
      final runner = FakeTestRunner();
      await _run(
        _context(
          {
            'lib/a.dart': [],
            'test/a_test.dart': ['../lib/a.dart'],
          },
          ['M lib/a.dart'],
          runner: runner,
        ),
      );

      expect(runner.calls.single.files, [path('test/a_test.dart')]);
    });
  });

  group('the divergence test', () {
    test(
      'uncommitted changes in the closure skip the run with one warning',
      () async {
        final runner = FakeTestRunner();
        final findings = await _run(
          _context(
            {
              'lib/a.dart': [],
              'test/a_test.dart': ['../lib/a.dart'],
            },
            ['M lib/a.dart'],
            runner: runner,
            dirty: {'lib/a.dart', 'test/a_test.dart'},
          ),
        );

        expect(runner.calls, isEmpty);
        final finding = findings.single;
        expect(finding.message, _skip);
        expect(finding.severity, Severity.warning);
        expect(finding.severityLocked, isTrue);
        expect(finding.rule, affectedRule);
        expect(finding.location, Location.wholeFile(path('lib/a.dart')));
      },
    );

    test('the warning for an untracked import target sits at the import '
        'directive of the first importing file', () async {
      final runner = FakeTestRunner();
      final findings = await _run(
        _context(
          {
            'lib/a.dart': ['gen.dart'],
            'test/a_test.dart': ['../lib/a.dart', '../lib/gen.dart'],
          },
          ['M lib/a.dart'],
          runner: runner,
          dirty: {'lib/gen.dart'},
        ),
      );

      expect(runner.calls, isEmpty);
      // Importers in path order: lib/a.dart before test/a_test.dart.
      expect(
        findings.single.location,
        Location(
          path('lib/a.dart'),
          const Position(1, 8),
          const Position(1, 16),
        ),
      );
      expect(findings.single.message, contains('1 file(s)'));
    });

    test(
      'the warning for a divergent file of the snapshot sits at the file',
      () async {
        final findings = await _run(
          _context(
            {
              'lib/a.dart': [],
              'test/a_test.dart': ['../lib/a.dart'],
            },
            ['M test/a_test.dart'],
            dirty: {'test/a_test.dart'},
          ),
        );

        expect(
          findings.single.location,
          Location.wholeFile(path('test/a_test.dart')),
        );
      },
    );

    test('the warning for a divergent file absent from the snapshot that no '
        'closure file imports sits at the file', () async {
      final findings = await _run(
        _context(
          {'test/a_test.dart': []},
          ['M test/a_test.dart'],
          dirty: {'analysis_options.yaml'},
        ),
      );

      expect(
        findings.single.location,
        Location.wholeFile(path('analysis_options.yaml')),
      );
    });

    test('the first divergent path in path order is the location', () async {
      final findings = await _run(
        _context(
          {
            'lib/a.dart': [],
            'lib/b.dart': [],
            'test/a_test.dart': ['../lib/a.dart', '../lib/b.dart'],
          },
          ['M test/a_test.dart'],
          dirty: {'lib/b.dart', 'lib/a.dart'},
        ),
      );

      expect(findings.single.location.path, path('lib/a.dart'));
      expect(findings.single.message, contains('2 file(s)'));
    });

    test('divergence after the run discards the results and reports the '
        'warning', () async {
      final runner = FakeTestRunner(
        fallback: TestRunResult(
          failures: [
            FailedTest(
              file: path('test/a_test.dart'),
              line: 1,
              column: 1,
              name: 'fails',
            ),
          ],
        ),
      );
      final context = _context(
        {'test/a_test.dart': []},
        ['M test/a_test.dart'],
        runner: runner,
        answers: [
          {},
          {'test/a_test.dart'},
        ],
      );

      final findings = await _run(context);

      expect(runner.calls, hasLength(1));
      expect(findings.single.message, _skip.replaceFirst('2 ', '1 '));
      expect(findings.single.severity, Severity.warning);
      expect(findings.single.severityLocked, isTrue);
    });

    test('divergence is asked about the closure the selection computed, '
        'before and after', () async {
      final files = {
        'lib/a.dart': <String>[],
        'test/a_test.dart': ['../lib/a.dart'],
        'lib/unrelated.dart': <String>[],
      };
      final context = _context(files, ['M lib/a.dart']);

      await _run(context);

      final expected = selectAffectedTests(
        graph: await context.importGraph,
        changes: context.changes,
        packages: context.packages,
        snapshotPaths: {for (final key in files.keys) path(key)},
      ).closure;
      expect(context.divergentCalls, [expected, expected]);
      expect(expected, isNot(contains(path('lib/unrelated.dart'))));
    });

    test(
      'uncommitted changes outside the closure do not skip the run',
      () async {
        final runner = FakeTestRunner();
        final context = _context(
          {
            'lib/a.dart': [],
            'lib/unrelated.dart': [],
            'test/a_test.dart': ['../lib/a.dart'],
          },
          ['M lib/a.dart'],
          runner: runner,
          dirty: {'lib/unrelated.dart', 'README.md'},
        );

        expect(await _run(context), isEmpty);
        expect(runner.calls, hasLength(1));
      },
    );
  });
}

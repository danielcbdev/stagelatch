import 'dart:async';

import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/config/settings.dart';
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/pipeline.dart';
import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/fix.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_check.dart';
import '../../support/fake_clock.dart';
import '../../support/fake_git_repository.dart';
import '../../support/fake_working_tree.dart';

const _preCommit = RunRequest(entry: PreCommitEntry());

Pipeline _pipeline(
  FakeGitRepository git,
  List<Check> checks, {
  FakeClock? clock,
}) => Pipeline(
  git: git,
  configLoader: ConfigLoader(const StructuredDocuments(), FakeWorkingTree()),
  registry: CheckRegistry(checks),
  documents: const StructuredDocuments(),
  clock: clock ?? FakeClock(),
  toolVersion: Version.parse('0.1.0'),
);

/// A staged config whose pre-commit hook runs [selectors].
String _config(List<String> selectors, {String more = ''}) =>
    'hooks:\n  pre-commit: [${selectors.join(', ')}]\n$more';

FakeGitRepository _git(
  List<String> selectors, {
  String more = '',
  Map<String, Object> files = const {},
}) => FakeGitRepository(
  index: {
    'stagelatch.yaml': _config(selectors, more: more),
    ...files,
  },
);

Future<RunReport> _run(
  FakeGitRepository git,
  List<Check> checks, {
  RunRequest request = _preCommit,
  FakeClock? clock,
}) async => (await _pipeline(git, checks, clock: clock).run(request)).single;

void main() {
  group('findings', () {
    test('are sorted, whatever order the checks finish in', () async {
      final gate = Completer<void>();
      late final FakeCheck slow;
      late final FakeCheck fast;
      slow = FakeCheck(
        'slow',
        onRun: (_) async {
          await gate.future;
          return CheckResult(findings: [slow.finding('a.yaml')]);
        },
      );
      fast = FakeCheck(
        'fast',
        onRun: (_) async {
          gate.complete();
          return CheckResult(
            findings: [fast.finding('b.yaml'), fast.finding('a.yaml', line: 9)],
          );
        },
      );

      final report = await _run(_git(['slow', 'fast']), [slow, fast]);

      expect(
        report.findings.map((f) => (f.location.path.value, f.rule.check)),
        [('a.yaml', 'slow'), ('a.yaml', 'fast'), ('b.yaml', 'fast')],
      );
    });

    test('do not depend on the order of the registry', () async {
      FakeCheck check(String id, String path) {
        late final FakeCheck self;
        return self = FakeCheck(
          id,
          onRun: (_) async => CheckResult(findings: [self.finding(path)]),
        );
      }

      List<Check> checks() => [
        check('alpha', 'b.yaml'),
        check('beta', 'a.yaml'),
      ];

      final forward = await _run(_git(['alpha', 'beta']), checks());
      final backward = await _run(
        _git(['alpha', 'beta']),
        checks().reversed.toList(),
      );

      expect(forward.findings, backward.findings);
      expect(forward.verdict, backward.verdict);
    });

    test('of a rule the hook did not select are dropped', () async {
      late final FakeCheck alpha;
      alpha = FakeCheck(
        'alpha',
        rules: ['one', 'two'],
        onRun: (_) async => CheckResult(
          findings: [
            alpha.finding('a.yaml'),
            alpha.finding('a.yaml', rule: 'two'),
          ],
        ),
      );

      final report = await _run(_git(['alpha/two']), [alpha]);

      expect(report.findings.single.rule, const RuleId('alpha', 'two'));
    });

    test('follow the levels of the rules map', () async {
      late final FakeCheck alpha;
      alpha = FakeCheck(
        'alpha',
        rules: ['one', 'two'],
        onRun: (_) async => CheckResult(
          findings: [
            alpha.finding('a.yaml'),
            alpha.finding('b.yaml', rule: 'two'),
          ],
        ),
      );

      final report = await _run(
        _git([
          'alpha',
        ], more: 'rules:\n  alpha/one: off\n  alpha/two: warning\n'),
        [alpha],
      );

      expect(report.findings.single.severity, Severity.warning);
      expect(report.verdict, Verdict.pass);
    });

    test('on excluded paths are dropped', () async {
      late final FakeCheck alpha;
      alpha = FakeCheck(
        'alpha',
        onRun: (_) async => CheckResult(
          findings: [
            alpha.finding('lib/generated/a.dart'),
            alpha.finding('lib/b.dart'),
          ],
        ),
      );

      final report = await _run(
        _git(['alpha'], more: 'exclude: ["lib/generated/**"]\n'),
        [alpha],
      );

      expect(report.findings.single.location.path, RepoPath('lib/b.dart'));
    });
  });

  group('verdict', () {
    FakeCheck reporting(Severity severity) {
      late final FakeCheck self;
      return self = FakeCheck(
        'alpha',
        onRun: (_) async =>
            CheckResult(findings: [self.finding('a.yaml', severity: severity)]),
      );
    }

    test('passes with no finding', () async {
      final report = await _run(_git(['alpha']), [FakeCheck('alpha')]);

      expect(report.verdict, Verdict.pass);
      expect(report.findings, isEmpty);
    });

    test('passes with warnings alone', () async {
      final report = await _run(_git(['alpha']), [reporting(Severity.warning)]);

      expect(report.verdict, Verdict.pass);
      expect(report.findings, hasLength(1));
    });

    test('fails with one error', () async {
      final report = await _run(_git(['alpha']), [reporting(Severity.error)]);

      expect(report.verdict, Verdict.fail);
    });
  });

  group('which checks run', () {
    test('a check with no selected rule does not run', () async {
      final alpha = FakeCheck('alpha');
      final beta = FakeCheck('beta');

      await _run(_git(['alpha']), [alpha, beta]);

      expect(alpha.runCount, 1);
      expect(beta.runCount, 0);
    });

    test('the selectors come from the hook of the entry point', () async {
      final alpha = FakeCheck('alpha');
      final beta = FakeCheck('beta');
      final git = FakeGitRepository(
        index: {
          'stagelatch.yaml':
              'hooks:\n  pre-commit: [alpha]\n  pre-push: [beta]\n',
        },
      );

      await _run(
        git,
        [alpha, beta],
        request: const RunRequest(
          entry: PrePushEntry(remote: 'origin', refs: []),
        ),
      );

      expect(alpha.runCount, 0);
      expect(beta.runCount, 1);
    });

    test('ci runs the union of both hooks by default', () async {
      final alpha = FakeCheck('alpha');
      final beta = FakeCheck('beta');
      final git = FakeGitRepository(
        index: {
          'stagelatch.yaml':
              'hooks:\n  pre-commit: [alpha]\n  pre-push: [beta]\n',
        },
      );

      await _run(git, [
        alpha,
        beta,
      ], request: const RunRequest(entry: CiEntry(baseRef: 'origin/main')));

      expect(alpha.runCount, 1);
      expect(beta.runCount, 1);
    });
  });

  group('the context a check receives', () {
    test('describes the run', () async {
      final alpha = FakeCheck('alpha', rules: ['one', 'two']);
      final changes = ChangeSet([
        FileChange(path: RepoPath('a.yaml'), kind: ChangeKind.added),
      ]);
      final git = FakeGitRepository(
        index: {
          'stagelatch.yaml': _config([
            'alpha/one',
          ], more: 'assets:\n  max_file_size: 1KB\n'),
          'a.yaml': 'x: 1\n',
        },
        commits: {
          'base': {'a.yaml': 'x: 0\n'},
        },
        runs: [
          ResolvedRun(
            snapshot: const IndexSnapshot(),
            base: const CommitSnapshot('base'),
            changes: changes,
            targetBranch: 'release/1.2',
            label: 'index',
          ),
        ],
      );

      await _run(git, [alpha]);
      final context = alpha.lastContext!;

      expect(context.entry, EntryKind.preCommit);
      expect(context.changes, same(changes));
      expect(context.targetBranch, 'release/1.2');
      expect(await context.snapshot.readText(RepoPath('a.yaml')), 'x: 1\n');
      expect(await context.base?.readText(RepoPath('a.yaml')), 'x: 0\n');
      expect(context.isEnabled(const RuleId('alpha', 'one')), isTrue);
      expect(context.isEnabled(const RuleId('alpha', 'two')), isFalse);
      expect(context.settings<AssetsSettings>().maxFileSize, 1024);
      expect(context.packages.packages, isEmpty);
    });

    test('has no base on the first commit', () async {
      final alpha = FakeCheck('alpha');

      await _run(_git(['alpha']), [alpha]);

      expect(alpha.lastContext!.base, isNull);
    });

    test('has no Dart toolchain before 0.1.0', () async {
      final alpha = FakeCheck('alpha');

      await _run(_git(['alpha']), [alpha]);

      expect(() => alpha.lastContext!.dart, throwsUnsupportedError);
    });
  });

  group('failures', () {
    test('a check that throws becomes an internal error naming it', () {
      final boom = FakeCheck(
        'boom',
        onRun: (_) async => throw StateError('broken'),
      );

      expect(
        () => _run(_git(['boom']), [boom]),
        throwsA(
          isA<InternalException>()
              .having((e) => e.where, 'where', 'check "boom"')
              .having((e) => e.message, 'message', 'Bad state: broken')
              .having((e) => e.cause, 'cause', isA<StateError>())
              .having((e) => e.stackTrace, 'stackTrace', isNotNull),
        ),
      );
    });

    test('a usage error raised inside a check is not rewrapped', () {
      final check = FakeCheck(
        'alpha',
        onRun: (_) async => throw const UsageException('Run: dart pub get'),
      );

      expect(
        () => _run(_git(['alpha']), [check]),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            'Run: dart pub get',
          ),
        ),
      );
    });

    test('an invalid config stops the run before any check', () async {
      final alpha = FakeCheck('alpha');
      final git = FakeGitRepository(index: {'stagelatch.yaml': 'nope: 1\n'});

      await expectLater(
        () => _run(git, [alpha]),
        throwsA(isA<ConfigException>()),
      );
      expect(alpha.runCount, 0);
    });
  });

  group('timing', () {
    test('records how long each check took, in registry order', () async {
      final clock = FakeClock();
      FakeCheck taking(String id, int milliseconds) => FakeCheck(
        id,
        onRun: (_) async {
          clock.advance(Duration(milliseconds: milliseconds));
          return const CheckResult();
        },
      );

      final report = await _run(_git(['beta', 'alpha']), [
        taking('alpha', 40),
        taking('beta', 7),
      ], clock: clock);

      expect(report.timings.map((t) => t.id), ['alpha', 'beta']);
      expect(report.timings.first.duration, isNot(Duration.zero));
      expect(report.total, const Duration(milliseconds: 47));
      expect(report.budgetExceeded, isFalse);
    });

    test('counts the findings of each check after filtering', () async {
      late final FakeCheck alpha;
      alpha = FakeCheck(
        'alpha',
        rules: ['one', 'two', 'three'],
        onRun: (_) async => CheckResult(
          findings: [
            alpha.finding('a.yaml'),
            alpha.finding('b.yaml', rule: 'two', severity: Severity.warning),
            alpha.finding('c.yaml', rule: 'three'),
          ],
        ),
      );

      final report = await _run(
        _git(['alpha'], more: 'rules:\n  alpha/three: off\n'),
        [alpha],
      );

      final timing = report.timings.single;
      expect((timing.errors, timing.warnings, timing.fixed), (1, 1, 0));
    });

    test(
      'exceeding the budget sets the flag and changes nothing else',
      () async {
        Future<RunReport> runTaking(Duration duration) {
          final clock = FakeClock();
          late final FakeCheck alpha;
          alpha = FakeCheck(
            'alpha',
            onRun: (_) async {
              clock.advance(duration);
              return CheckResult(findings: [alpha.finding('a.yaml')]);
            },
          );
          return _run(_git(['alpha'], more: 'time_budget: 2s\n'), [
            alpha,
          ], clock: clock);
        }

        final within = await runTaking(const Duration(seconds: 2));
        final over = await runTaking(const Duration(seconds: 3));

        expect(within.budgetExceeded, isFalse);
        expect(over.budgetExceeded, isTrue);
        expect(over.findings, within.findings);
        expect(over.verdict, within.verdict);
      },
    );
  });

  group('fix phase (ADR-0014)', () {
    const formatRule = RuleId('fmt', 'unformatted');

    /// A fix-phase check that wants `a.dart` to read "fixed".
    FakeCheck formatter() {
      late final FakeCheck self;
      return self = FakeCheck(
        'fmt',
        phase: CheckPhase.fix,
        rules: ['unformatted'],
        onRun: (context) async {
          final text = await context.snapshot.readText(RepoPath('a.dart'));
          if (text == 'fixed') return const CheckResult();
          return CheckResult(
            findings: [self.finding('a.dart', rule: 'unformatted')],
            fixes: [
              Fix(rule: formatRule, path: RepoPath('a.dart'), content: 'fixed'),
            ],
          );
        },
      );
    }

    /// A verify-phase check that records what it reads from `a.dart`.
    (FakeCheck, List<String?>) reader() {
      final seen = <String?>[];
      final check = FakeCheck(
        'reader',
        onRun: (context) async {
          seen.add(await context.snapshot.readText(RepoPath('a.dart')));
          return const CheckResult();
        },
      );
      return (check, seen);
    }

    test('applies fixes to the index, and verify sees the result', () async {
      final git = _git(['fmt', 'reader'], files: {'a.dart': 'raw'});
      final (check, seen) = reader();

      final report = await _run(git, [check, formatter()]);

      expect(git.appliedFixes.single.path, RepoPath('a.dart'));
      expect(git.index['a.dart'], 'fixed');
      expect(seen, ['fixed']);
      expect(report.findings, isEmpty);
      expect(report.verdict, Verdict.pass);
      expect(report.fixes, [
        AppliedFix(
          rule: formatRule,
          path: RepoPath('a.dart'),
          worktreeUpdated: true,
        ),
      ]);
      expect(report.timings.firstWhere((t) => t.id == 'fmt').fixed, 1);
    });

    test(
      'with fixes disallowed, keeps the finding and applies nothing',
      () async {
        final git = _git(['fmt', 'reader'], files: {'a.dart': 'raw'});
        final (check, seen) = reader();

        final report = await _run(
          git,
          [formatter(), check],
          request: const RunRequest(entry: PreCommitEntry(), allowFixes: false),
        );

        expect(git.appliedFixes, isEmpty);
        expect(seen, ['raw']);
        expect(report.findings.single.rule, formatRule);
        expect(report.fixes, isEmpty);
        expect(report.verdict, Verdict.fail);
      },
    );

    test('never applies fixes to a commit snapshot', () async {
      final git = FakeGitRepository(
        commits: {
          'head': {
            'stagelatch.yaml': _config(['fmt']),
            'a.dart': 'raw',
          },
        },
        runs: [
          ResolvedRun(
            snapshot: const CommitSnapshot('head'),
            base: null,
            changes: ChangeSet(const []),
            targetBranch: 'main',
            label: 'main',
          ),
        ],
      );

      final report = await _run(git, [formatter()]);

      expect(git.appliedFixes, isEmpty);
      expect(report.findings.single.rule, formatRule);
    });

    test('does not fix an excluded path, and drops its finding', () async {
      final git = _git(
        ['fmt'],
        more: 'exclude: ["*.dart"]\n',
        files: {'a.dart': 'raw'},
      );

      final report = await _run(git, [formatter()]);

      expect(git.appliedFixes, isEmpty);
      expect(git.index['a.dart'], 'raw');
      expect(report.findings, isEmpty);
    });

    test('does not fix on behalf of a rule that is off', () async {
      final git = _git(
        ['fmt'],
        more: 'rules:\n  fmt/unformatted: off\n',
        files: {'a.dart': 'raw'},
      );

      final report = await _run(git, [formatter()]);

      expect(git.appliedFixes, isEmpty);
      expect(report.findings, isEmpty);
    });

    test('a fix for a rule set to warning is still applied', () async {
      final git = _git(
        ['fmt'],
        more: 'rules:\n  fmt/unformatted: warning\n',
        files: {'a.dart': 'raw'},
      );

      final report = await _run(git, [formatter()]);

      expect(git.index['a.dart'], 'fixed');
      expect(report.findings, isEmpty);
    });
  });

  group('the report', () {
    test('describes the run it is about', () async {
      final git = FakeGitRepository(
        index: {
          'stagelatch.yaml': _config(['alpha']),
        },
        changes: ChangeSet([
          FileChange(path: RepoPath('a.yaml'), kind: ChangeKind.added),
          FileChange(path: RepoPath('b.yaml'), kind: ChangeKind.deleted),
        ]),
      );

      final report = await _run(git, [FakeCheck('alpha')]);

      expect(report.entry, EntryKind.preCommit);
      expect(report.label, 'index');
      expect(report.files, 2);
      expect(report.suppressed, 0);
      expect(report.baselined, 0);
      expect(report.notices, isEmpty);
    });

    test('carries the notices of the config loader', () async {
      final pipeline = Pipeline(
        git: FakeGitRepository(),
        configLoader: ConfigLoader(
          const StructuredDocuments(),
          FakeWorkingTree({'stagelatch.yaml': 'time_budget: 1s\n'}),
        ),
        registry: CheckRegistry(const []),
        documents: const StructuredDocuments(),
        clock: FakeClock(),
        toolVersion: Version.parse('0.1.0'),
      );

      final report = (await pipeline.run(_preCommit)).single;

      expect(report.notices, [configNotStagedNotice]);
    });

    test('there is one report per resolved run, in order', () async {
      ResolvedRun pushed(String sha, String branch) => ResolvedRun(
        snapshot: CommitSnapshot(sha),
        base: null,
        changes: ChangeSet(const []),
        targetBranch: branch,
        label: branch,
      );
      final git = FakeGitRepository(
        commits: {'one': const {}, 'two': const {}},
        runs: [pushed('one', 'feature-a'), pushed('two', 'feature-b')],
      );

      final reports = await _pipeline(git, const []).run(
        const RunRequest(
          entry: PrePushEntry(remote: 'origin', refs: []),
        ),
      );

      expect(reports.map((r) => r.label), ['feature-a', 'feature-b']);
      expect(reports.every((r) => r.entry == EntryKind.prePush), isTrue);
    });

    test('no resolved run means no report', () async {
      final git = FakeGitRepository(runs: const []);

      expect(await _pipeline(git, const []).run(_preCommit), isEmpty);
    });

    test('the all flag is passed on to git', () async {
      final git = _git(['alpha']);

      await _run(git, [
        FakeCheck('alpha'),
      ], request: const RunRequest(entry: PreCommitEntry(), all: true));

      expect(git.lastResolveAll, isTrue);
    });
  });
}

/// The one use case behind `run` and `ci`.
library;

import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/config/default_hooks.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/finding_filters.dart';
import 'package:stagelatch/src/application/pipeline/pipeline_check_context.dart';
import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/pipeline/selection.dart';
import 'package:stagelatch/src/application/ports/clock.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Judges what an entry point publishes (docs/architecture.md, 5.3).
///
/// Hooks and CI differ only in the [RunRequest] they pass: there is no
/// hook-only or CI-only logic anywhere below this class (ADR-0005).
final class Pipeline {
  /// Creates a pipeline over the given ports.
  new({
    required this._git,
    required this._configLoader,
    required this._registry,
    required this._documents,
    required this._clock,
    required this._toolVersion,
  });

  final GitRepository _git;
  final ConfigLoader _configLoader;
  final CheckRegistry _registry;
  final Documents _documents;
  final Clock _clock;
  final Version _toolVersion;

  /// Resolves [request] to the snapshots it concerns and judges each one.
  ///
  /// Returns one report per snapshot: one for pre-commit and ci, one per
  /// pushed branch for pre-push, none when there is nothing to judge.
  ///
  /// Throws [ConfigException] for an invalid configuration, before any
  /// check runs, and [InternalException] naming the check when one fails
  /// unexpectedly. Findings are never thrown; they are in the report.
  Future<List<RunReport>> run(RunRequest request) async {
    final resolved = await _git.resolve(request.entry, all: request.all);
    return [for (final run in resolved) await _judge(request, run)];
  }

  Future<RunReport> _judge(RunRequest request, ResolvedRun run) async {
    final started = _clock.elapsed;
    final entry = request.entry.kind;

    // ADR-0015: the configuration that judges a snapshot is the one in it.
    final loaded = await _configLoader.load(
      _git.files(run.snapshot),
      toolVersion: _toolVersion,
      catalog: _registry,
    );
    final config = loaded.config;
    final selection = Selection.of(config.hooks[_hookOf(entry)] ?? const []);

    // Built on demand, because the fix phase changes what the snapshot
    // holds: `files` then returns a view of the updated index.
    CheckContext context() => PipelineCheckContext(
      entry: entry,
      changes: run.changes,
      snapshot: _git.files(run.snapshot),
      base: switch (run.base) {
        final base? => _git.files(base),
        null => null,
      },
      documents: _documents,
      targetBranch: run.targetBranch,
      selection: selection,
      config: config,
    );

    List<Finding> filtered(List<Finding> findings) => applyExclude(
      applyLevels(applySelection(findings, selection), config.rules),
      config.exclude,
    );

    final outcomes = <String, _Outcome>{};

    // Fix phase (ADR-0014). Sequential, in registry order, so that two
    // fixers can never race on one file. A commit snapshot is immutable,
    // so there the same checks only report.
    final mayFix = request.allowFixes && run.snapshot is IndexSnapshot;
    for (final check in _registry.checks) {
      if (check.phase != CheckPhase.fix || !selection.runs(check)) continue;
      final (result, duration) = await _timed(check, context());
      var findings = filtered(result.findings);
      var applied = const <AppliedFix>[];
      if (mayFix) {
        // A fix is applied only for a finding that survived the filters:
        // a rule that is off, or an excluded path, is left untouched.
        final wanted = [
          for (final fix in result.fixes)
            if (findings.any(
              (finding) =>
                  finding.rule == fix.rule && finding.location.path == fix.path,
            ))
              fix,
        ];
        if (wanted.isNotEmpty) {
          applied = await _git.applyFixes(wanted);
          findings = [
            for (final finding in findings)
              if (!applied.any(
                (fix) =>
                    fix.rule == finding.rule &&
                    fix.path == finding.location.path,
              ))
                finding,
          ];
        }
      }
      outcomes[check.id] = _Outcome(findings, applied, duration);
    }

    // Verify phase, against the snapshot as the fix phase left it, so that
    // every location refers to what will actually be published.
    final verifying = [
      for (final check in _registry.checks)
        if (check.phase == CheckPhase.verify && selection.runs(check)) check,
    ];
    final verifyContext = context();
    final results = await Future.wait([
      for (final check in verifying) _timed(check, verifyContext),
    ]);
    // Results are consumed by index: completion order never reaches the
    // report (ADR-0003).
    for (final (index, check) in verifying.indexed) {
      final (result, duration) = results[index];
      outcomes[check.id] = _Outcome(
        filtered(result.findings),
        const [],
        duration,
      );
    }

    final ran = [
      for (final check in _registry.checks)
        if (outcomes[check.id] case final outcome?) (check.id, outcome),
    ];
    final findings = [for (final (_, outcome) in ran) ...outcome.findings]
      ..sort(Finding.compare);
    final total = _clock.elapsed - started;

    return RunReport(
      entry: entry,
      label: run.label,
      files: run.changes.length,
      verdict: findings.any((finding) => finding.severity == Severity.error)
          ? Verdict.fail
          : Verdict.pass,
      findings: List.unmodifiable(findings),
      fixes: List.unmodifiable([
        for (final (_, outcome) in ran) ...outcome.applied,
      ]),
      timings: List.unmodifiable([
        for (final (id, outcome) in ran)
          CheckTiming(
            id: id,
            duration: outcome.duration,
            errors: outcome.count(Severity.error),
            warnings: outcome.count(Severity.warning),
            fixed: outcome.applied.length,
          ),
      ]),
      total: total,
      timeBudget: config.timeBudget,
      // The budget is only ever reported. Skipping or shortening a check
      // would make the verdict depend on the machine (ADR-0003).
      budgetExceeded: total > config.timeBudget,
      suppressed: 0,
      baselined: 0,
      notices: loaded.notices,
    );
  }

  /// Runs [check] and measures it.
  Future<(CheckResult, Duration)> _timed(
    Check check,
    CheckContext context,
  ) async {
    final started = _clock.elapsed;
    try {
      final result = await check.run(context);
      return (result, _clock.elapsed - started);
    } on StagelatchException {
      // Already says what happened and maps to its own exit code.
      rethrow;
      // Anything else is a bug in the check. It is caught here, and only
      // here besides the command runner, because this is the one place
      // that still knows which check was running, and that name is what
      // makes the resulting report actionable.
    } on Object catch (error, stackTrace) {
      throw InternalException(
        error.toString(),
        where: 'check "${check.id}"',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// The key under `hooks` that holds the selectors of [entry].
  static String _hookOf(EntryKind entry) => switch (entry) {
    EntryKind.preCommit => preCommitHook,
    EntryKind.prePush => prePushHook,
    EntryKind.ci => ciHook,
  };
}

/// What one check contributed to a run.
final class _Outcome {
  const new(this.findings, this.applied, this.duration);

  /// Its findings, after filtering and after fixes were applied.
  final List<Finding> findings;

  /// The fixes written to the index on its behalf.
  final List<AppliedFix> applied;

  final Duration duration;

  int count(Severity severity) =>
      findings.where((finding) => finding.severity == severity).length;
}

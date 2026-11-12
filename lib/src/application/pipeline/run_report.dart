/// What a pipeline run is asked to do, and what it reports back.
library;

import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';

/// One invocation of the pipeline.
final class RunRequest {
  /// Creates a request for [entry].
  const new({required this.entry, this.all = false, this.allowFixes = true});

  /// What started the run.
  final EntryPoint entry;

  /// Whether every file of the snapshot counts as changed (`--all`).
  final bool all;

  /// Whether fixes may be written to the index. False for `--no-fix`; fixes
  /// are never written to a commit snapshot, whatever this says.
  final bool allowFixes;
}

/// The outcome of a run.
enum Verdict {
  /// No finding with severity error. Warnings do not block.
  pass,

  /// At least one finding with severity error.
  fail,
}

/// How one check did in a run.
final class CheckTiming {
  /// Creates the record.
  const new({
    required this.id,
    required this.duration,
    required this.errors,
    required this.warnings,
    required this.fixed,
  });

  /// The id of the check.
  final String id;

  /// How long the check ran.
  final Duration duration;

  /// Its findings with severity error, after filtering.
  final int errors;

  /// Its findings with severity warning, after filtering.
  final int warnings;

  /// How many files it fixed in the index.
  final int fixed;
}

/// Everything a reporter needs to present one judged snapshot.
///
/// Apart from the durations, a report is a pure function of the snapshot,
/// its base, the configuration and the tool version (ADR-0003).
final class RunReport {
  /// Creates a report.
  const new({
    required this.entry,
    required this.label,
    required this.files,
    required this.verdict,
    required this.findings,
    required this.fixes,
    required this.timings,
    required this.total,
    required this.budgetExceeded,
    required this.suppressed,
    required this.baselined,
    required this.notices,
  });

  /// Which entry point started the run.
  final EntryKind entry;

  /// A short name for what was judged: `index`, or the pushed branch.
  final String label;

  /// The number of changed paths.
  final int files;

  /// Whether the change may proceed.
  final Verdict verdict;

  /// What remains to be shown, sorted with `Finding.compare`.
  final List<Finding> findings;

  /// The fixes that were written to the index.
  final List<AppliedFix> fixes;

  /// One record per check that ran, in registry order.
  final List<CheckTiming> timings;

  /// How long the whole run took.
  final Duration total;

  /// Whether [total] is over the configured time budget. Informational:
  /// the budget never changes what runs.
  final bool budgetExceeded;

  /// How many findings inline `stagelatch:ignore` comments silenced.
  final int suppressed;

  /// How many findings the baseline silenced.
  final int baselined;

  /// Sentences the user should see with the report.
  final List<String> notices;
}

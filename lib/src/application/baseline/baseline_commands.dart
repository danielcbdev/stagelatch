/// `baseline create` and `baseline prune`
/// (docs/specs/baseline-and-suppression.md section 4.4).
library;

import 'package:stagelatch/src/application/baseline/baseline.dart';
import 'package:stagelatch/src/application/baseline/baseline_codec.dart';
import 'package:stagelatch/src/application/config/default_hooks.dart';
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/pipeline.dart';
import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/working_tree.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';

/// Writes and trims the baseline file in the working tree.
///
/// Both commands judge the index with every file in scope, the selectors
/// of `hooks.ci`, no fixes and no baseline. Neither stages anything: that
/// stays with the developer (security rule S4).
final class BaselineCommands {
  /// Creates the commands over [_pipeline] and [_workingTree].
  const new(this._pipeline, this._workingTree);

  final Pipeline _pipeline;
  final WorkingTree _workingTree;

  static const RunRequest _request = RunRequest(
    entry: PreCommitEntry(),
    all: true,
    allowFixes: false,
    hook: ciHook,
    useBaseline: false,
  );

  /// Writes every current finding as an entry and returns the message to
  /// print.
  ///
  /// Throws a [UsageException] when the file exists and [force] is false.
  Future<String> create({required bool force}) async {
    final current = await _pipeline.currentBaseline(_request);
    final path = current.path;
    if (!force && await _workingTree.exists(path)) {
      throw UsageException(
        '$path already exists. Use --force to overwrite, '
        'or run: stagelatch baseline prune',
      );
    }
    await _workingTree.writeText(path, encodeBaseline(current.baseline));
    final count = current.baseline.entries.length;
    return 'Wrote $count ${count == 1 ? 'entry' : 'entries'} to $path. '
        'Stage it to take effect.';
  }

  /// Lowers each entry to the findings that still match it, drops the ones
  /// that reach zero and returns the message to print.
  ///
  /// It never adds an entry and never raises a count.
  Future<String> prune() async {
    final current = await _pipeline.currentBaseline(_request);
    final path = current.path;
    final text = await _workingTree.readText(path);
    if (text == null) return 'No baseline at $path.';

    final existing = decodeBaseline(text, path: path);
    final present = {
      for (final entry in current.baseline.entries) _key(entry): entry.count,
    };
    final kept = <BaselineEntry>[];
    for (final entry in existing.entries) {
      final matching = present[_key(entry)] ?? 0;
      final count = matching < entry.count ? matching : entry.count;
      if (count > 0) kept.add(entry.withCount(count));
    }
    await _workingTree.writeText(path, encodeBaseline(Baseline(kept)));
    final removed = existing.entries.length - kept.length;
    return 'Removed $removed stale ${removed == 1 ? 'entry' : 'entries'}; '
        '${kept.length} remain.';
  }

  static (RuleId, RepoPath, String) _key(BaselineEntry entry) =>
      (entry.rule, entry.path, entry.fingerprint);
}

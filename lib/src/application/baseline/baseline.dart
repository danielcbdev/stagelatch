/// The accepted findings of a legacy codebase
/// (docs/specs/baseline-and-suppression.md section 4).
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';

/// One kind of finding the repository has agreed to live with.
@immutable
final class BaselineEntry {
  /// Creates an entry that absorbs up to [count] findings.
  new({
    required this.rule,
    required this.path,
    required this.fingerprint,
    required this.count,
  }) {
    if (count < 1) throw RangeError.value(count, 'count', 'Must be positive.');
  }

  /// The rule of the findings it absorbs.
  final RuleId rule;

  /// The file they are in.
  final RepoPath path;

  /// The fingerprint of their snippet (see `fingerprintOf`).
  final String fingerprint;

  /// How many findings with this rule, path and fingerprint it absorbs.
  final int count;

  /// The same entry absorbing [count] findings.
  BaselineEntry withCount(int count) => BaselineEntry(
    rule: rule,
    path: path,
    fingerprint: fingerprint,
    count: count,
  );

  /// The order of the file: path, then rule, then fingerprint.
  static int compare(BaselineEntry a, BaselineEntry b) {
    final byPath = a.path.compareTo(b.path);
    if (byPath != 0) return byPath;
    final byRule = a.rule.compareTo(b.rule);
    if (byRule != 0) return byRule;
    return a.fingerprint.compareTo(b.fingerprint);
  }

  @override
  bool operator ==(Object other) =>
      other is BaselineEntry &&
      other.rule == rule &&
      other.path == path &&
      other.fingerprint == fingerprint &&
      other.count == count;

  @override
  int get hashCode => Object.hash(rule, path, fingerprint, count);

  @override
  String toString() => 'BaselineEntry($rule, $path, $fingerprint, $count)';
}

/// What a baseline written now would hold, and where it belongs.
final class CurrentBaseline {
  /// Creates the pair.
  const new({required this.baseline, required this.path});

  /// One entry per kind of finding the run reported.
  final Baseline baseline;

  /// The `baseline` path of the configuration in the judged snapshot.
  final RepoPath path;
}

/// The entries of a baseline file.
@immutable
final class Baseline {
  /// Creates a baseline of [entries].
  const new(this.entries);

  /// No entry: what a missing file means.
  static const Baseline empty = Baseline([]);

  /// The entries, in no particular order.
  final List<BaselineEntry> entries;

  /// How many findings the baseline absorbs in all.
  int get total => entries.fold(0, (sum, entry) => sum + entry.count);
}

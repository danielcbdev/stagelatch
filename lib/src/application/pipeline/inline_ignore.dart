/// Inline `stagelatch:ignore` comments (ADR-0010,
/// docs/specs/baseline-and-suppression.md, section 2).
library;

import 'package:stagelatch/src/application/config/check_catalog.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// The rule the suppression filter reports for an unknown id. No check owns
/// it, so the registry declares it on the pipeline's behalf.
const RuleId invalidIgnoreRule = RuleId('stagelatch', 'invalid-ignore');

const String _marker = 'stagelatch:ignore';

/// One rule id written in an ignore comment.
final class IgnoreId {
  /// Creates an id found at [column] of its line.
  const new({required this.text, required this.column});

  /// The id as written.
  final String text;

  /// The 1-based column of its first character.
  final int column;
}

/// One ignore comment: it covers findings on [line] and on the next line.
final class IgnoreDirective {
  /// Creates a directive.
  const new({required this.line, required this.ids});

  /// The 1-based line of the comment.
  final int line;

  /// The ids it names, in the order written. Never empty.
  final List<IgnoreId> ids;
}

/// What the filter kept, how many findings it removed, and the findings it
/// adds for unknown ids.
final class IgnoreOutcome {
  /// Creates an outcome.
  const new({
    required this.kept,
    required this.suppressed,
    required this.invalid,
  });

  /// The findings no comment covers, in their original order.
  final List<Finding> kept;

  /// How many findings a comment covered.
  final int suppressed;

  /// One `stagelatch/invalid-ignore` finding per unknown id in a changed
  /// file, sorted.
  final List<Finding> invalid;
}

/// The comment opener of [path]'s file kind, or null when the kind has no
/// inline form.
String? commentOpenerFor(RepoPath path) => switch (path.extension) {
  '.dart' => '//',
  '.yaml' || '.yml' => '#',
  _ => null,
};

/// The ignore comments of [text].
///
/// Each line is searched with `indexOf`, never a regular expression, so a
/// hostile line costs time proportional to its length (security S6).
List<IgnoreDirective> scanIgnores(
  String text, {
  required String commentOpener,
}) {
  final directives = <IgnoreDirective>[];
  var lineNumber = 0;
  var start = 0;
  while (true) {
    var end = text.indexOf('\n', start);
    if (end < 0) end = text.length;
    lineNumber++;
    var lineEnd = end;
    if (lineEnd > start && text.codeUnitAt(lineEnd - 1) == 0x0D) lineEnd--;
    final ids = _idsOnLine(text, start, lineEnd, commentOpener);
    if (ids.isNotEmpty) {
      directives.add(IgnoreDirective(line: lineNumber, ids: ids));
    }
    if (end == text.length) return directives;
    start = end + 1;
  }
}

/// The ids of the first marker on the line `text[start, end)`.
List<IgnoreId> _idsOnLine(String text, int start, int end, String opener) {
  var from = start;
  while (true) {
    final at = text.indexOf(opener, from);
    if (at < 0 || at + opener.length > end) return const [];
    // The next search starts one character later, so `///` still finds
    // `//` at its second slash. A failed candidate costs at most the spaces
    // after it, which hold no opener, so the scan stays linear.
    from = at + 1;
    var i = _skipSpaces(text, at + opener.length, end);
    if (i + _marker.length > end || !text.startsWith(_marker, i)) continue;
    i += _marker.length;
    if (i < end && !_isSpace(text.codeUnitAt(i))) continue;
    return _readIds(text, i, end, start);
  }
}

/// Ids separated by commas with optional spaces. The first id that is not
/// followed by a comma ends the list; what follows is free text.
List<IgnoreId> _readIds(String text, int from, int end, int lineStart) {
  final ids = <IgnoreId>[];
  var i = _skipSpaces(text, from, end);
  while (i < end) {
    final tokenStart = i;
    while (i < end && !_endsId(text.codeUnitAt(i))) {
      i++;
    }
    if (i == tokenStart) break;
    ids.add(
      IgnoreId(
        text: text.substring(tokenStart, i),
        column: tokenStart - lineStart + 1,
      ),
    );
    i = _skipSpaces(text, i, end);
    if (i >= end || text.codeUnitAt(i) != 0x2C /* , */ ) break;
    i = _skipSpaces(text, i + 1, end);
  }
  return ids;
}

int _skipSpaces(String text, int from, int end) {
  var i = from;
  while (i < end && _isSpace(text.codeUnitAt(i))) {
    i++;
  }
  return i;
}

bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;

bool _endsId(int unit) => _isSpace(unit) || unit == 0x2C /* , */;

/// Removes the findings that an ignore comment covers and reports unknown
/// ids in changed files.
///
/// A comment on line n covers findings of the rules it names whose start
/// line is n or n + 1. An id is known when [catalog] has it, when it is
/// under `analyze/`, when its check prefix is in [trustedCustomCheckIds]
/// (`--no-custom-checks`), or when it is in [additionalKnownRules]
/// (handshake / config / selectors). [invalidIgnoreRule] is known too but
/// suppresses nothing, because its findings are added after this filter
/// has run.
Future<IgnoreOutcome> applyInlineIgnores(
  List<Finding> findings, {
  required SnapshotFiles snapshot,
  required ChangeSet changes,
  required CheckCatalog catalog,
  Set<String> trustedCustomCheckIds = const {},
  Set<RuleId> additionalKnownRules = const {},
}) async {
  final directives = <RepoPath, List<IgnoreDirective>>{};
  Future<List<IgnoreDirective>> directivesOf(RepoPath path) async {
    final cached = directives[path];
    if (cached != null) return cached;
    final opener = commentOpenerFor(path);
    final text = opener == null ? null : await snapshot.readText(path);
    return directives[path] = opener == null || text == null
        ? const []
        : scanIgnores(text, commentOpener: opener);
  }

  final kept = <Finding>[];
  var suppressed = 0;
  for (final finding in findings) {
    final line = finding.location.start.line;
    final rule = finding.rule.toString();
    final covered = (await directivesOf(finding.location.path)).any(
      (d) =>
          (line == d.line || line == d.line + 1) &&
          d.ids.any((id) => id.text == rule),
    );
    if (covered) {
      suppressed++;
    } else {
      kept.add(finding);
    }
  }

  final invalid = <Finding>[];
  for (final change in changes.present) {
    for (final directive in await directivesOf(change.path)) {
      for (final id in directive.ids) {
        if (_isKnown(
          id.text,
          catalog,
          trustedCustomCheckIds: trustedCustomCheckIds,
          additionalKnownRules: additionalKnownRules,
        )) {
          continue;
        }
        invalid.add(
          Finding(
            rule: invalidIgnoreRule,
            severity: Severity.warning,
            message: 'Unknown rule "${id.text}" in stagelatch:ignore.',
            location: Location(
              change.path,
              Position(directive.line, id.column),
              Position(directive.line, id.column + id.text.length),
            ),
          ),
        );
      }
    }
  }
  invalid.sort(Finding.compare);
  return IgnoreOutcome(kept: kept, suppressed: suppressed, invalid: invalid);
}

bool _isKnown(
  String text,
  CheckCatalog catalog, {
  Set<String> trustedCustomCheckIds = const {},
  Set<RuleId> additionalKnownRules = const {},
}) {
  if (text.startsWith('analyze/') && text.length > 'analyze/'.length) {
    return true;
  }
  final RuleId id;
  try {
    id = RuleId.parse(text);
  } on FormatException {
    return false;
  }
  if (trustedCustomCheckIds.contains(id.check)) return true;
  if (additionalKnownRules.contains(id)) return true;
  return catalog.hasRule(id);
}

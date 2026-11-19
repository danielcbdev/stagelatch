import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// A [Check] whose behavior a test supplies.
final class FakeCheck implements Check {
  /// Creates a check named [id] with the rules `<id>/<name>` for each of
  /// [rules]. [onRun] produces its result; without it the check reports
  /// nothing.
  new(
    this.id, {
    this.phase = CheckPhase.verify,
    List<String> rules = const ['one'],
    this.hasDynamicRules = false,
    this.onRun,
  }) : _ruleNames = rules;

  @override
  final String id;

  @override
  final CheckPhase phase;

  @override
  final bool hasDynamicRules;

  final List<String> _ruleNames;

  /// What the check does when run.
  final Future<CheckResult> Function(CheckContext context)? onRun;

  /// How many times the pipeline ran this check.
  int runCount = 0;

  /// The context of the most recent run.
  CheckContext? lastContext;

  @override
  List<RuleDescriptor> get rules => [
    for (final name in _ruleNames)
      RuleDescriptor(
        id: RuleId(id, name),
        defaultSeverity: Severity.error,
        summary: 'A fake rule.',
      ),
  ];

  @override
  Future<CheckResult> run(CheckContext context) async {
    runCount++;
    lastContext = context;
    return await onRun?.call(context) ?? const CheckResult();
  }

  /// A finding of this check's rule [rule] at [path].
  Finding finding(
    String path, {
    String rule = 'one',
    int line = 1,
    Severity severity = Severity.error,
    String message = 'message',
  }) => Finding(
    rule: RuleId(id, rule),
    severity: severity,
    message: message,
    location: Location(RepoPath(path), Position(line, 1), Position(line, 2)),
  );
}

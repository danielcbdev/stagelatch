/// The `analyze` check (docs/specs/rules.md, `analyze`).
library;

import 'package:stagelatch/src/checks/analyze/analysis_scope.dart';
import 'package:stagelatch/src/checks/analyze/analyze_settings.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Reports the diagnostics of the project's SDK for the files of the
/// configured scope, each as `analyze/<code>`.
final class AnalyzeCheck implements Check {
  /// Creates the check.
  const new();

  @override
  String get id => 'analyze';

  @override
  CheckPhase get phase => CheckPhase.verify;

  @override
  List<RuleDescriptor> get rules => const [];

  @override
  bool get hasDynamicRules => true;

  @override
  Future<CheckResult> run(CheckContext context) async {
    // Nothing a Dart diagnostic depends on changed: the toolchain is never
    // started (architecture section 6).
    if (!triggersAnalysis(context.changes)) return const CheckResult();
    final settings = context.settings<AnalyzeSettings>();
    final files = await analysisScope(context, settings.scope);
    if (files.isEmpty) return const CheckResult();
    final diagnostics = await context.dart.diagnose(files);
    return CheckResult(
      findings: [
        for (final diagnostic in diagnostics)
          if (_severity(diagnostic.severity, settings.failOn)
              case final severity?)
            Finding(
              rule: RuleId('analyze', diagnostic.code),
              severity: severity,
              message: diagnostic.message,
              location: diagnostic.location,
            ),
      ],
    );
  }

  /// A severity listed in `fail_on` blocks; otherwise errors and warnings
  /// warn and infos are dropped.
  static Severity? _severity(
    DiagnosticSeverity severity,
    Set<DiagnosticSeverity> failOn,
  ) {
    if (failOn.contains(severity)) return Severity.error;
    return severity == DiagnosticSeverity.info ? null : Severity.warning;
  }
}

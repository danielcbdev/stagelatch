/// SARIF 2.1.0 report for `stagelatch ci` (docs/specs/cli.md, section 7).
library;

import 'dart:convert';

import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/reporter.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Writes one SARIF 2.1.0 document for exactly one pipeline run.
///
/// Maps are built in the documented key order and encoded by
/// `JsonEncoder`; no string is ever concatenated into the output (S5).
/// Only rules that produced a result appear in `tool.driver.rules`.
final class SarifReporter implements Reporter {
  /// Creates a reporter that writes to `out`.
  ///
  /// `describe` is typically the registry's `descriptorOf`. A null
  /// descriptor (an analyzer code, for example) uses the rule id as the
  /// short description.
  new(this._out, {required this._toolVersion, required this._describe});

  final StringSink _out;
  final String _toolVersion;
  final RuleDescriptor? Function(RuleId) _describe;

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  @override
  void report(List<RunReport> runs) {
    if (runs.length > 1) {
      throw ArgumentError.value(
        runs.length,
        'runs',
        'SARIF accepts exactly one run, or none.',
      );
    }
    final findings = runs.isEmpty ? const <Finding>[] : runs.single.findings;
    final object = <String, Object?>{
      r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
      'version': '2.1.0',
      'runs': [
        {
          'tool': {
            'driver': {
              'name': 'stagelatch',
              'version': _toolVersion,
              'rules': _rules(findings),
            },
          },
          'results': [for (final finding in findings) _result(finding)],
        },
      ],
    };
    _out.writeln(_encoder.convert(object));
  }

  List<Map<String, Object?>> _rules(List<Finding> findings) {
    final ids = <RuleId>{};
    for (final finding in findings) {
      ids.add(finding.rule);
    }
    final sorted = ids.toList()..sort();
    return [
      for (final id in sorted)
        {
          'id': id.toString(),
          'shortDescription': {'text': _describe(id)?.summary ?? id.toString()},
        },
    ];
  }

  Map<String, Object?> _result(Finding finding) {
    final location = finding.location;
    return {
      'ruleId': finding.rule.toString(),
      'level': finding.severity == Severity.error ? 'error' : 'warning',
      'message': {'text': finding.message},
      'locations': [
        {
          'physicalLocation': {
            'artifactLocation': {
              'uri': _uri(location.path.value),
              'uriBaseId': '%SRCROOT%',
            },
            'region': {
              'startLine': location.start.line,
              'startColumn': location.start.column,
              'endLine': location.end.line,
              'endColumn': location.end.column,
            },
          },
        },
      ],
    };
  }

  /// Repository-relative path with each segment percent-encoded.
  static String _uri(String path) => Uri(pathSegments: path.split('/')).path;
}

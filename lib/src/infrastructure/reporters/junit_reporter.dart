/// JUnit XML report for `stagelatch ci` (docs/specs/cli.md, section 7).
library;

import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/reporter.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/reporters/xml_writer.dart';

/// Writes one JUnit XML document for exactly one pipeline run.
///
/// Every element goes through [XmlWriter]; repository text is never
/// concatenated into markup (S5).
final class JunitReporter implements Reporter {
  /// Creates a reporter that writes to the given sink.
  new(this._out);

  final StringSink _out;

  @override
  void report(List<RunReport> runs) {
    if (runs.length > 1) {
      throw ArgumentError.value(
        runs.length,
        'runs',
        'JUnit accepts exactly one run, or none.',
      );
    }
    final report = runs.isEmpty ? null : runs.single;
    final timings = report?.timings ?? const <CheckTiming>[];
    final findings = report?.findings ?? const <Finding>[];
    final checkIds = {for (final timing in timings) timing.id};
    final byCheck = <String, List<Finding>>{
      for (final timing in timings) timing.id: <Finding>[],
    };
    final orphan = <Finding>[];
    for (final finding in findings) {
      final check = finding.rule.check;
      if (checkIds.contains(check)) {
        byCheck[check]!.add(finding);
      } else {
        orphan.add(finding);
      }
    }

    final testcaseCount = timings.length + (orphan.isEmpty ? 0 : 1);
    var failures = 0;
    for (final timing in timings) {
      if (byCheck[timing.id]!.any((f) => f.severity == Severity.error)) {
        failures++;
      }
    }
    if (orphan.any((f) => f.severity == Severity.error)) {
      failures++;
    }

    final writer = XmlWriter(_out)
      ..startElement('testsuite', {
        'name': 'stagelatch',
        'tests': '$testcaseCount',
        'failures': '$failures',
        'errors': '0',
        'time': _seconds(report?.total ?? Duration.zero),
      });
    for (final timing in timings) {
      _testcase(
        writer,
        name: timing.id,
        time: timing.duration,
        findings: byCheck[timing.id]!,
      );
    }
    if (orphan.isNotEmpty) {
      _testcase(
        writer,
        name: 'stagelatch',
        time: Duration.zero,
        findings: orphan,
      );
    }
    writer.endElement();
    _out.write('\n');
  }

  void _testcase(
    XmlWriter writer, {
    required String name,
    required Duration time,
    required List<Finding> findings,
  }) {
    final attrs = {
      'classname': 'stagelatch',
      'name': name,
      'time': _seconds(time),
    };
    final errors = [
      for (final finding in findings)
        if (finding.severity == Severity.error) finding,
    ];
    final warnings = [
      for (final finding in findings)
        if (finding.severity == Severity.warning) finding,
    ];
    if (errors.isEmpty && warnings.isEmpty) {
      writer.emptyElement('testcase', attrs);
      return;
    }
    writer.startElement('testcase', attrs);
    for (final finding in errors) {
      writer
        ..startElement('failure', {
          'message': '${finding.rule}: ${finding.message}',
        })
        ..text(_location(finding))
        ..endElement();
    }
    if (warnings.isNotEmpty) {
      writer
        ..startElement('system-out')
        ..text(
          [
            for (final finding in warnings)
              '${finding.rule}: ${finding.message} (${_location(finding)})',
          ].join('\n'),
        )
        ..endElement();
    }
    writer.endElement();
  }

  static String _location(Finding finding) {
    final location = finding.location;
    return '${location.path.value}:${location.start.line}:'
        '${location.start.column}';
  }

  /// Formats [duration] as seconds with three decimal places.
  static String _seconds(Duration duration) {
    final ms = duration.inMilliseconds;
    final whole = ms ~/ 1000;
    final frac = (ms % 1000).toString().padLeft(3, '0');
    return '$whole.$frac';
  }
}

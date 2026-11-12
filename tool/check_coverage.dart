/// Fails the build when line coverage of the pure modules is below the floor.
///
/// Usage: `dart run tool/check_coverage.dart [lcov file]`, after
/// `dart test --coverage-path=coverage/lcov.info`.
library;

import 'dart:convert';
import 'dart:io';

/// Minimum line coverage, in percent, of `domain`, `checks` and
/// `application` taken together (docs/engineering/testing.md, section 6).
const int coverageFloorPercent = 90;

/// Where `dart test --coverage-path` is asked to write its report.
const String defaultLcovPath = 'coverage/lcov.info';

/// The modules held to the floor. Adapters and the cli are covered by
/// adapter and acceptance tests and have no numeric threshold.
const _coveredDirectories = [
  'lib/src/domain/',
  'lib/src/checks/',
  'lib/src/application/',
];

/// Line totals of the covered modules.
final class CoverageSummary {
  /// Creates a summary of [found] instrumented lines, [hit] of them run.
  const new({required this.found, required this.hit});

  /// Instrumented lines.
  final int found;

  /// Instrumented lines executed at least once.
  final int hit;

  /// Coverage in percent; 100 when there is nothing to cover.
  double get percent => found == 0 ? 100 : hit * 100 / found;
}

/// Whether a summary meets the floor, and the line to print.
final class CoverageVerdict {
  /// Creates a verdict.
  const new({required this.passed, required this.message});

  /// True when coverage is at or above [coverageFloorPercent].
  final bool passed;

  /// The single line reported to the user.
  final String message;
}

/// Whether [path], as written in an lcov `SF:` record, belongs to a module
/// held to the floor. Accepts both `/` and `\` separators.
bool isCoveredPath(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return _coveredDirectories.any(normalized.contains);
}

/// Sums the `DA:` records of [lcov] for files accepted by [isCoveredPath].
///
/// Malformed records are skipped rather than reported: this tool judges
/// coverage, not the report format.
CoverageSummary summarizeLcov(String lcov) {
  var found = 0;
  var hit = 0;
  var included = false;
  for (final line in const LineSplitter().convert(lcov)) {
    if (line.startsWith('SF:')) {
      included = isCoveredPath(line.substring('SF:'.length));
    } else if (included && line.startsWith('DA:')) {
      // DA:<line number>,<execution count>[,<checksum>]
      final fields = line.substring('DA:'.length).split(',');
      final count = fields.length < 2 ? null : int.tryParse(fields[1]);
      if (count == null) continue;
      found++;
      if (count > 0) hit++;
    }
  }
  return CoverageSummary(found: found, hit: hit);
}

/// Compares [summary] with [coverageFloorPercent].
CoverageVerdict verdictFor(CoverageSummary summary) {
  if (summary.found == 0) {
    return const CoverageVerdict(
      passed: true,
      message: 'No covered files yet.',
    );
  }
  // Integer comparison, and a percentage truncated to one decimal, so that
  // 89.96% is never printed as "90.0%" next to a failure.
  final passed = summary.hit * 100 >= coverageFloorPercent * summary.found;
  final shown = (summary.percent * 10).floor() / 10;
  return CoverageVerdict(
    passed: passed,
    message:
        'Line coverage of domain, checks and application: '
        '${shown.toStringAsFixed(1)}% (floor $coverageFloorPercent%).',
  );
}

/// Reads the lcov report named by the first argument, or [defaultLcovPath],
/// and sets a non-zero exit code when coverage is below the floor.
void main(List<String> arguments) {
  final path = arguments.isEmpty ? defaultLcovPath : arguments.first;
  final report = File(path);
  if (!report.existsSync()) {
    stderr.writeln(
      'No coverage report at $path. '
      'Run: dart test --coverage-path=$defaultLcovPath',
    );
    exitCode = 1;
    return;
  }
  final verdict = verdictFor(summarizeLcov(report.readAsStringSync()));
  stdout.writeln(verdict.message);
  exitCode = verdict.passed ? 0 : 1;
}

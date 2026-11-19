import 'package:test/test.dart';

import '../../tool/check_coverage.dart';

void main() {
  group('isCoveredPath', () {
    test('matches the three pure modules', () {
      expect(isCoveredPath('/r/lib/src/domain/finding.dart'), isTrue);
      expect(isCoveredPath('/r/lib/src/checks/pubspec/a.dart'), isTrue);
      expect(isCoveredPath('lib/src/application/errors.dart'), isTrue);
    });

    test('does not match adapters, the cli or the version file', () {
      expect(isCoveredPath('/r/lib/src/infrastructure/git/a.dart'), isFalse);
      expect(isCoveredPath('/r/lib/src/cli/runner.dart'), isFalse);
      expect(isCoveredPath('/r/lib/src/version.dart'), isFalse);
    });

    test('accepts Windows separators', () {
      expect(isCoveredPath(r'C:\r\lib\src\domain\finding.dart'), isTrue);
    });
  });

  group('summarizeLcov', () {
    test('counts the lines of covered modules only', () {
      const lcov = '''
SF:/r/lib/src/domain/a.dart
DA:1,3
DA:2,0
LF:2
LH:1
end_of_record
SF:/r/lib/src/cli/b.dart
DA:1,0
LF:1
LH:0
end_of_record
SF:/r/lib/src/checks/c.dart
DA:7,1
DA:9,1
end_of_record
''';

      final summary = summarizeLcov(lcov);

      expect(summary.found, 4);
      expect(summary.hit, 3);
      expect(summary.percent, 75);
    });

    test('reports nothing found when no covered module has a file', () {
      const lcov = '''
SF:/r/lib/src/cli/b.dart
DA:1,1
end_of_record
''';

      final summary = summarizeLcov(lcov);

      expect(summary.found, 0);
      expect(summary.hit, 0);
    });

    test('ignores malformed DA lines instead of failing', () {
      const lcov = '''
SF:/r/lib/src/domain/a.dart
DA:
DA:x,y
DA:4,2
end_of_record
''';

      expect(summarizeLcov(lcov).found, 1);
    });
  });

  group('verdictFor', () {
    test('passes at or above the floor', () {
      const summary = CoverageSummary(found: 10, hit: 9);

      expect(verdictFor(summary).passed, isTrue);
      expect(
        verdictFor(summary).message,
        'Line coverage of domain, checks and application: 90.0% '
        '(floor 90%).',
      );
    });

    test('fails below the floor', () {
      const summary = CoverageSummary(found: 1000, hit: 899);

      expect(verdictFor(summary).passed, isFalse);
      expect(
        verdictFor(summary).message,
        'Line coverage of domain, checks and application: 89.9% '
        '(floor 90%).',
      );
    });

    test('passes with a notice when nothing is covered yet', () {
      const summary = CoverageSummary(found: 0, hit: 0);

      expect(verdictFor(summary).passed, isTrue);
      expect(verdictFor(summary).message, 'No covered files yet.');
    });
  });
}

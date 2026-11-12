import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/fix.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

Finding _finding({
  String path = 'a.dart',
  int line = 1,
  int column = 1,
  String rule = 'analyze/x',
  String message = 'm',
  Severity severity = Severity.error,
}) => Finding(
  rule: RuleId.parse(rule),
  severity: severity,
  message: message,
  location: Location(
    RepoPath(path),
    Position(line, column),
    Position(line, column),
  ),
);

void main() {
  group('Finding.compare', () {
    test('orders by path, line, column, rule, message', () {
      final expected = [
        _finding(),
        _finding(message: 'n'),
        _finding(rule: 'analyze/y'),
        _finding(column: 2),
        _finding(line: 2),
        _finding(path: 'b.dart'),
      ];
      final shuffled = [
        expected[4],
        expected[1],
        expected[5],
        expected[0],
        expected[3],
        expected[2],
      ]..sort(Finding.compare);

      expect(shuffled, expected);
    });

    test('returns zero for equal findings', () {
      expect(Finding.compare(_finding(), _finding()), 0);
    });
  });

  group('Finding', () {
    test('is equal when every field is equal', () {
      expect(_finding(), _finding());
      expect(_finding().hashCode, _finding().hashCode);
    });

    test('differs when any field differs', () {
      expect(_finding(), isNot(_finding(path: 'b.dart')));
      expect(_finding(), isNot(_finding(line: 2)));
      expect(_finding(), isNot(_finding(rule: 'analyze/y')));
      expect(_finding(), isNot(_finding(message: 'n')));
      expect(_finding(), isNot(_finding(severity: Severity.warning)));
    });

    test('prints location, severity, rule and message', () {
      expect(
        _finding(path: 'pubspec.yaml', line: 14, column: 5).toString(),
        'pubspec.yaml:14:5 error analyze/x: m',
      );
    });
  });

  group('Fix', () {
    Fix fix({String path = 'a.dart', String content = 'x'}) => Fix(
      rule: const RuleId('format', 'unformatted'),
      path: RepoPath(path),
      content: content,
    );

    test('is equal when rule, path and content are equal', () {
      expect(fix(), fix());
      expect(fix().hashCode, fix().hashCode);
    });

    test('differs when path or content differs', () {
      expect(fix(), isNot(fix(path: 'b.dart')));
      expect(fix(), isNot(fix(content: 'y')));
    });
  });
}

import 'package:stagelatch/src/application/baseline/fingerprint.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_snapshot_files.dart';

Finding _finding({
  String rule = 'pubspec/path-dependency',
  String path = 'lib/a.dart',
  int line = 1,
  int? endLine,
}) => Finding(
  rule: RuleId.parse(rule),
  severity: Severity.error,
  message: 'message',
  location: Location(
    RepoPath(path),
    Position(line, 1),
    Position(endLine ?? line, 5),
  ),
);

void main() {
  group('normalizeSnippet', () {
    test('trims, collapses inner whitespace and joins lines', () {
      expect(
        normalizeSnippet(['  import   "a.dart";\t', '  x  ']),
        'import "a.dart"; x',
      );
    });

    test('tabs and runs of spaces inside a line become one space', () {
      expect(normalizeSnippet(['a\t\t b   c']), 'a b c');
    });

    test('nothing is nothing', () {
      expect(normalizeSnippet(const []), '');
      expect(normalizeSnippet(['   ']), '');
    });
  });

  group('fingerprintOf', () {
    test('is the SHA-256 of rule, path and normalized snippet', () async {
      final snapshot = FakeSnapshotFiles({
        'lib/a.dart': '// header\n  import   "a.dart";\t\n  x  \n',
      });

      expect(
        await fingerprintOf(_finding(line: 2, endLine: 3), snapshot),
        'b77d0129d49b6f0645e16694e723081514149857816c9532247404a69ee4bbc7',
      );
    });

    test('does not depend on the line number', () async {
      final before = FakeSnapshotFiles({'lib/a.dart': 'x\nbad();\n'});
      final after = FakeSnapshotFiles({
        'lib/a.dart': '1\n2\n3\n4\n5\n6\n7\nbad();\n',
      });

      expect(
        await fingerprintOf(_finding(line: 2), before),
        await fingerprintOf(_finding(line: 8), after),
      );
    });

    test('does not depend on the formatting of the snippet', () async {
      final tight = FakeSnapshotFiles({'lib/a.dart': 'bad( 1 );\n'});
      final loose = FakeSnapshotFiles({'lib/a.dart': '    bad(   1 );\t\n'});

      expect(
        await fingerprintOf(_finding(), tight),
        await fingerprintOf(_finding(), loose),
      );
    });

    test('depends on rule, path and snippet', () async {
      final snapshot = FakeSnapshotFiles({
        'lib/a.dart': 'one\ntwo\n',
        'lib/b.dart': 'one\ntwo\n',
      });
      final base = await fingerprintOf(_finding(), snapshot);

      expect(
        await fingerprintOf(_finding(rule: 'pubspec/other'), snapshot),
        isNot(base),
      );
      expect(
        await fingerprintOf(_finding(path: 'lib/b.dart'), snapshot),
        isNot(base),
      );
      expect(await fingerprintOf(_finding(line: 2), snapshot), isNot(base));
    });

    test('the snippet runs from the start line to the end line, '
        'inclusive', () async {
      final snapshot = FakeSnapshotFiles({'lib/a.dart': 'a\nb\nc\nd\n'});

      expect(
        await fingerprintOf(_finding(line: 2, endLine: 3), snapshot),
        isNot(await fingerprintOf(_finding(line: 2), snapshot)),
      );
      expect(
        await fingerprintOf(_finding(line: 2, endLine: 3), snapshot),
        await fingerprintOf(
          _finding(line: 2, endLine: 3),
          FakeSnapshotFiles({'lib/a.dart': '0\nb\nc\nz\n'}),
        ),
      );
    });

    test('CRLF line endings do not change it', () async {
      final lf = FakeSnapshotFiles({'lib/a.dart': 'a\nb\n'});
      final crlf = FakeSnapshotFiles({'lib/a.dart': 'a\r\nb\r\n'});

      expect(
        await fingerprintOf(_finding(endLine: 2), lf),
        await fingerprintOf(_finding(endLine: 2), crlf),
      );
    });

    test('a file that is not text, or is absent, has an empty '
        'snippet', () async {
      final binary = FakeSnapshotFiles({
        '.env': [0x00, 0x01],
      });
      final absent = FakeSnapshotFiles({});
      final finding = _finding(
        rule: 'sensitive-files/credentials',
        path: '.env',
      );

      expect(
        await fingerprintOf(finding, binary),
        '3261794e290419dcaf41b8283ae714246dd53430aecb3ca42e49ac5a65133a43',
      );
      expect(
        await fingerprintOf(finding, absent),
        await fingerprintOf(finding, binary),
      );
    });

    test('lines past the end of the file are an empty snippet', () async {
      final snapshot = FakeSnapshotFiles({'lib/a.dart': 'a\n'});

      expect(
        await fingerprintOf(_finding(line: 40), snapshot),
        await fingerprintOf(_finding(line: 50), snapshot),
      );
    });
  });
}

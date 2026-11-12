import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:test/test.dart';

void main() {
  final path = RepoPath('lib/a.dart');
  final location = Location.wholeFile(path);

  group('SnapshotEntry', () {
    test('is equal when path, mode and blob id are equal', () {
      SnapshotEntry entry({String blobId = 'abc'}) =>
          SnapshotEntry(path: path, mode: FileMode.regular, blobId: blobId);

      expect(entry(), entry());
      expect(entry().hashCode, entry().hashCode);
      expect(entry(), isNot(entry(blobId: 'def')));
    });
  });

  group('FileMode', () {
    test('only regular and executable entries carry readable content', () {
      expect(FileMode.regular.isFile, isTrue);
      expect(FileMode.executable.isFile, isTrue);
      expect(FileMode.symlink.isFile, isFalse);
      expect(FileMode.gitlink.isFile, isFalse);
    });
  });

  test('the text size limit is 5 MiB', () {
    expect(maxTextBytes, 5 * 1024 * 1024);
  });

  group('CheckResult', () {
    test('is empty by default', () {
      const result = CheckResult();

      expect(result.findings, isEmpty);
      expect(result.fixes, isEmpty);
    });
  });

  group('DocumentResult', () {
    test('has exactly three shapes', () {
      String describe(DocumentResult result) => switch (result) {
        DocumentMissing() => 'missing',
        DocumentInvalid(:final reason) => 'invalid: $reason',
        DocumentParsed(:final root) => 'parsed: ${root.runtimeType}',
      };

      expect(describe(const DocumentMissing()), 'missing');
      expect(
        describe(DocumentInvalid(location: location, reason: 'bad')),
        'invalid: bad',
      );
      expect(
        describe(DocumentParsed(LocatedScalar(location: location, value: 1))),
        'parsed: LocatedScalar',
      );
    });
  });

  group('LocatedNode', () {
    test('has exactly three shapes, each with a location', () {
      final scalar = LocatedScalar(location: location, value: 'x');
      final list = LocatedList(location: location, items: [scalar]);
      final map = LocatedMap(
        location: location,
        entries: {'key': LocatedEntry(keyLocation: location, value: list)},
      );

      String describe(LocatedNode node) => switch (node) {
        LocatedMap(:final entries) => 'map of ${entries.length}',
        LocatedList(:final items) => 'list of ${items.length}',
        LocatedScalar(:final value) => 'scalar $value',
      };

      expect(describe(map), 'map of 1');
      expect(describe(list), 'list of 1');
      expect(describe(scalar), 'scalar x');
      expect(map.entries['key']?.value, same(list));
      expect(map.location, location);
    });
  });

  group('FormatOutcome', () {
    test('is either formatted text or unparseable', () {
      String describe(FormatOutcome outcome) => switch (outcome) {
        Formatted(:final text) => text,
        Unparseable() => 'unparseable',
      };

      expect(describe(const Formatted('void main() {}\n')), 'void main() {}\n');
      expect(describe(const Unparseable()), 'unparseable');
    });
  });

  group('DartDiagnostic', () {
    test('carries the analyzer fields and an optional correction', () {
      final diagnostic = DartDiagnostic(
        location: location,
        code: 'unused_import',
        severity: DiagnosticSeverity.warning,
        message: 'Unused import.',
      );

      expect(diagnostic.code, 'unused_import');
      expect(diagnostic.severity, DiagnosticSeverity.warning);
      expect(diagnostic.location, location);
      expect(diagnostic.message, 'Unused import.');
      expect(diagnostic.correction, isNull);
    });
  });

  group('DartFileFacts', () {
    test('is empty by default', () {
      const facts = DartFileFacts();

      expect(facts.directives, isEmpty);
      expect(facts.annotatedDeclarations, isEmpty);
      expect(facts.testCalls, isEmpty);
      expect(facts.identifiers, isEmpty);
    });

    test('holds directives, annotated declarations and test calls', () {
      final facts = DartFileFacts(
        directives: [
          Directive(
            kind: DirectiveKind.part,
            uri: 'a.g.dart',
            location: location,
          ),
        ],
        annotatedDeclarations: [
          AnnotatedDeclaration(
            name: 'Order',
            annotations: const ['JsonSerializable'],
            tokenHash: 'abc',
            location: location,
          ),
        ],
        testCalls: [
          TestCall(
            function: 'test',
            description: 'adds',
            groups: const ['cart'],
            location: location,
            skip: location,
          ),
        ],
      );

      expect(facts.directives.single.kind, DirectiveKind.part);
      expect(facts.directives.single.uri, 'a.g.dart');
      expect(facts.annotatedDeclarations.single.name, 'Order');
      expect(facts.annotatedDeclarations.single.tokenHash, 'abc');
      expect(facts.testCalls.single.groups, ['cart']);
      expect(facts.testCalls.single.skip, location);
      expect(facts.testCalls.single.solo, isNull);
    });
  });
}

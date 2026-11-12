import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_snapshot_files.dart';

const _documents = StructuredDocuments();

Future<DocumentResult> _yaml(Object content, {String path = 'p.yaml'}) =>
    _documents.yaml(FakeSnapshotFiles({path: content}), RepoPath(path));

Future<DocumentResult> _json(Object content, {String path = 'a.json'}) =>
    _documents.json(FakeSnapshotFiles({path: content}), RepoPath(path));

/// The root of a document that is expected to parse into a map.
Future<LocatedMap> _map(Future<DocumentResult> result) async {
  final resolved = await result;
  expect(resolved, isA<DocumentParsed>());
  final root = (resolved as DocumentParsed).root;
  expect(root, isA<LocatedMap>());
  return root as LocatedMap;
}

/// A document that is expected to be rejected.
Future<DocumentInvalid> _invalid(Future<DocumentResult> result) async {
  final resolved = await result;
  expect(resolved, isA<DocumentInvalid>());
  return resolved as DocumentInvalid;
}

void main() {
  group('yaml', () {
    test('returns 1-based locations for keys and values', () async {
      final root = await _map(
        _yaml(
          'name: app\n'
          'dependencies:\n'
          '  foo:\n'
          '    path: ../foo\n',
        ),
      );

      final dependencies = root.entries['dependencies']!;
      expect(dependencies.keyLocation.start, const Position(2, 1));
      expect(dependencies.keyLocation.end, const Position(2, 13));

      final foo = (dependencies.value as LocatedMap).entries['foo']!;
      final path = (foo.value as LocatedMap).entries['path']!;
      expect(path.keyLocation.start, const Position(4, 5));
      expect(path.value.location.start, const Position(4, 11));
      expect(path.value.location.end, const Position(4, 17));
      expect((path.value as LocatedScalar).value, '../foo');
    });

    test('locations carry the path of the file', () async {
      final root = await _map(
        _yaml('a: 1\n', path: 'packages/ui/pubspec.yaml'),
      );

      expect(root.location.path, RepoPath('packages/ui/pubspec.yaml'));
      expect(
        root.entries['a']!.keyLocation.path,
        RepoPath('packages/ui/pubspec.yaml'),
      );
    });

    test('keeps the types of scalars', () async {
      final root = await _map(
        _yaml(
          'int: 1\n'
          'double: 1.5\n'
          'bool: true\n'
          'nothing:\n'
          'text: hello\n'
          'quoted: "1"\n',
        ),
      );

      Object? value(String key) =>
          (root.entries[key]!.value as LocatedScalar).value;
      expect(value('int'), 1);
      expect(value('double'), 1.5);
      expect(value('bool'), isTrue);
      expect(value('nothing'), isNull);
      expect(value('text'), 'hello');
      expect(value('quoted'), '1');
    });

    test('parses sequences with a location per item', () async {
      final root = await _map(_yaml('items:\n  - a\n  - b\n'));

      final items = (root.entries['items']!.value as LocatedList).items;
      expect(items.map((item) => (item as LocatedScalar).value), ['a', 'b']);
      expect(items[0].location.start, const Position(2, 5));
      expect(items[1].location.start, const Position(3, 5));
    });

    test('keeps map entries in document order', () async {
      final root = await _map(_yaml('zebra: 1\napple: 2\nmango: 3\n'));

      expect(root.entries.keys, ['zebra', 'apple', 'mango']);
    });

    test('an empty document is a null scalar', () async {
      final result = await _yaml('');

      expect(result, isA<DocumentParsed>());
      final root = (result as DocumentParsed).root;
      expect(root, isA<LocatedScalar>());
      expect((root as LocatedScalar).value, isNull);
    });

    test('a missing file is DocumentMissing', () async {
      final result = await _documents.yaml(
        FakeSnapshotFiles(const {}),
        RepoPath('pubspec.yaml'),
      );

      expect(result, isA<DocumentMissing>());
    });

    test('a file that is not text is invalid at its first character', () async {
      final invalid = await _invalid(_yaml([0x00, 0x01]));

      expect(invalid.location, Location.wholeFile(RepoPath('p.yaml')));
      expect(invalid.reason, 'the file is not readable text');
    });

    test('invalid YAML is rejected at the parser position', () async {
      final invalid = await _invalid(_yaml('a: [1, 2'));

      expect(invalid.location.start, const Position(1, 9));
      expect(invalid.reason, isNotEmpty);
      expect(invalid.reason, isNot(endsWith('.')));
    });

    test('duplicate keys are invalid', () async {
      final invalid = await _invalid(_yaml('a: 1\na: 2\n'));

      expect(invalid.location.start, const Position(2, 1));
      expect(invalid.reason, 'Duplicate mapping key');
    });

    test('map keys that are not strings are invalid', () async {
      final invalid = await _invalid(_yaml('name: x\n1: a\n'));

      expect(invalid.location.start, const Position(2, 1));
      expect(invalid.reason, 'map keys must be strings');
    });

    test('a document that expands beyond the node limit is invalid', () async {
      String level(String name, String previous) =>
          '$name: &$name [${List.filled(10, '*$previous').join(', ')}]\n';
      final bomb = StringBuffer('a: &a [x, x, x, x, x, x, x, x, x, x]\n')
        ..write(level('b', 'a'))
        ..write(level('c', 'b'))
        ..write(level('d', 'c'))
        ..write(level('e', 'd'))
        ..write(level('f', 'e'));

      final invalid = await _invalid(_yaml(bomb.toString()));

      expect(invalid.reason, 'the document is too large');
    });

    test('flow collections nested too deeply are invalid', () async {
      final invalid = await _invalid(_yaml('a: ${'[' * 100000}'));

      expect(invalid.reason, 'the document is nested too deeply');
      expect(invalid.location, Location.wholeFile(RepoPath('p.yaml')));
    });

    test('flow nesting is accepted up to the limit and not beyond', () async {
      String nested(int depth) => 'a: ${'[' * depth}${']' * depth}\n';

      expect(await _yaml(nested(maxFlowNesting)), isA<DocumentParsed>());
      final invalid = await _invalid(_yaml(nested(maxFlowNesting + 1)));
      expect(invalid.reason, 'the document is nested too deeply');
    });

    test('many sibling collections are not deep nesting', () async {
      final siblings = 'a: [${List.filled(2000, '[1]').join(', ')}]\n';

      expect(await _yaml(siblings), isA<DocumentParsed>());
    });

    test('block sequences nested too deeply are invalid', () async {
      final invalid = await _invalid(_yaml('${'- ' * 100000}x'));

      expect(invalid.reason, 'the document is nested too deeply');
    });
  });

  group('json', () {
    test('returns located nodes for valid JSON', () async {
      final root = await _map(_json('{"type": "service_account"}'));

      final type = root.entries['type']!;
      expect((type.value as LocatedScalar).value, 'service_account');
      expect(type.keyLocation.start, const Position(1, 2));
      expect(type.value.location.start, const Position(1, 10));
    });

    test('accepts JSON indented with tabs', () async {
      final root = await _map(
        _json('{\n\t"a": 1,\n\t"b": {\n\t\t"c": [1, 2]\n\t}\n}\n'),
      );

      expect(root.entries.keys, ['a', 'b']);
      expect(root.entries['a']!.keyLocation.start, const Position(2, 2));
    });

    test('decodes string escapes', () async {
      final root = await _map(_json(r'{"a": "x\/y ç \n \" \\"}'));

      expect(
        (root.entries['a']!.value as LocatedScalar).value,
        'x/y ç \n " \\',
      );
    });

    test('rejects YAML that is not JSON', () async {
      final invalid = await _invalid(_json('a: 1'));

      expect(invalid.location.start, const Position(1, 1));
      expect(invalid.reason, isNotEmpty);
      expect(invalid.reason, isNot(endsWith('.')));
    });

    test('reports the line and column of a JSON error', () async {
      final invalid = await _invalid(_json('{\n  "a": 1,\n  "b": \n}'));

      expect(invalid.location.start, const Position(4, 1));
    });

    test('rejects JSON nested too deeply', () async {
      final invalid = await _invalid(_json('[' * 100000));

      expect(invalid.reason, 'the document is nested too deeply');
    });

    test('rejects an empty file', () async {
      expect(await _json(''), isA<DocumentInvalid>());
    });

    test('rejects duplicate keys', () async {
      final invalid = await _invalid(_json('{"a": 1, "a": 2}'));

      expect(invalid.reason, 'Duplicate mapping key');
    });

    test('a missing file is DocumentMissing', () async {
      final result = await _documents.json(
        FakeSnapshotFiles(const {}),
        RepoPath('a.json'),
      );

      expect(result, isA<DocumentMissing>());
    });

    test('a file that is not text is invalid', () async {
      final invalid = await _invalid(_json([0x00, 0x01]));

      expect(invalid.reason, 'the file is not readable text');
    });
  });
}

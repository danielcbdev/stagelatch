import 'dart:convert';
import 'dart:io';

import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/facts_codec.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';
import 'package:test/test.dart';

final _corpus = Directory('test/fixtures/facts_corpus');

Iterable<MapEntry<String, String>> _sources() sync* {
  final files = _corpus.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    yield MapEntry(file.path, file.readAsStringSync());
  }
}

final _a = RepoPath('a.dart');

/// A document of this version with the members of a valid one, and the
/// given ones replaced by something that may be wrongly typed.
String _document({
  Object? isWellFormed = true,
  Object? directives = const <Object?>[],
  Object? annotatedDeclarations = const <Object?>[],
  Object? testCalls = const <Object?>[],
  Object? identifiers = const <Object?>[],
}) => jsonEncode({
  'v': 1,
  'isWellFormed': isWellFormed,
  'directives': directives,
  'annotatedDeclarations': annotatedDeclarations,
  'testCalls': testCalls,
  'identifiers': identifiers,
});

Map<String, Object?> _directive({
  Object? kind = 'import',
  Object? uri = 'a',
  Object? start = const [1, 1],
}) => {
  'kind': kind,
  'uri': uri,
  'start': start,
  'end': const [1, 2],
};

void main() {
  test('the fixed corpus is there', () {
    expect(_sources(), hasLength(greaterThanOrEqualTo(6)));
  });

  test('encoding what was decoded gives the same text', () {
    for (final MapEntry(key: name, value: source) in _sources()) {
      final facts = const SyntacticFacts().extract(source, _a);
      final text = encodeFacts(facts);

      final decoded = decodeFacts(text, _a);

      expect(decoded, isNotNull, reason: name);
      expect(encodeFacts(decoded!), text, reason: name);
    }
  });

  test('every field of the facts is decoded', () {
    final source = File('test/fixtures/facts_corpus/tests.dart.txt')
        .readAsStringSync();
    final facts = const SyntacticFacts(
      testFunctions: {'test', 'group', 'testWidgets', 'myTest'},
    ).extract(source, _a);

    final decoded = decodeFacts(encodeFacts(facts), _a)!;

    expect(decoded.isWellFormed, facts.isWellFormed);
    expect(decoded.testCalls, hasLength(facts.testCalls.length));
    for (var i = 0; i < facts.testCalls.length; i++) {
      final want = facts.testCalls[i];
      final got = decoded.testCalls[i];
      expect(got.function, want.function);
      expect(got.description, want.description);
      expect(got.groups, want.groups);
      expect(got.location, want.location);
      expect(got.solo, want.solo);
      expect(got.skip, want.skip);
    }
  });

  test('the path is not stored: decoding for another path puts that path in '
      'every location', () {
    final source = File('test/fixtures/facts_corpus/tests.dart.txt')
        .readAsStringSync();
    final directives = File('test/fixtures/facts_corpus/directives.dart.txt')
        .readAsStringSync();
    final annotated = File('test/fixtures/facts_corpus/annotated.dart.txt')
        .readAsStringSync();
    final text = encodeFacts(
      const SyntacticFacts().extract(
        '$directives\n$annotated\n$source',
        RepoPath('only/here.dart'),
      ),
    );
    final other = RepoPath('lib/b.dart');

    final facts = decodeFacts(text, other)!;

    expect(text, isNot(contains('only/here')));
    expect(text, isNot(contains('lib/b.dart')));
    final locations = [
      for (final d in facts.directives) d.location,
      for (final d in facts.annotatedDeclarations) d.location,
      for (final c in facts.testCalls) ...[c.location, ?c.solo, ?c.skip],
    ];
    expect(locations, isNotEmpty);
    expect(locations.map((l) => l.path), everyElement(other));
    expect(facts.directives, isNotEmpty);
    expect(facts.annotatedDeclarations, isNotEmpty);
    expect(facts.testCalls, isNotEmpty);
  });

  test('identifiers are encoded sorted, so insertion order never changes the '
      'text', () {
    final one = encodeFacts(
      const DartFileFacts(identifiers: {'zeta', 'alpha', 'Beta', 'mid'}),
    );
    final two = encodeFacts(
      const DartFileFacts(identifiers: {'mid', 'Beta', 'alpha', 'zeta'}),
    );

    expect(one, two);
    final decoded = jsonDecode(one) as Map<String, Object?>;
    expect(decoded['identifiers'], ['Beta', 'alpha', 'mid', 'zeta']);
    expect(decodeFacts(one, _a)!.identifiers, {'zeta', 'alpha', 'Beta', 'mid'});
  });

  test('a file that is not well formed round-trips with empty declarations '
      'and calls', () {
    final source = File('test/fixtures/facts_corpus/unterminated.dart.txt')
        .readAsStringSync();
    final facts = const SyntacticFacts().extract(source, _a);
    expect(facts.isWellFormed, isFalse);

    final decoded = decodeFacts(encodeFacts(facts), _a)!;

    expect(decoded.isWellFormed, isFalse);
    expect(decoded.annotatedDeclarations, isEmpty);
    expect(decoded.testCalls, isEmpty);
    expect(decoded.directives.map((d) => d.uri), ['a.dart']);
  });

  test('tokenHash, groups, solo and skip survive', () {
    final orders = File('test/fixtures/facts_corpus/annotated.dart.txt')
        .readAsStringSync();
    final tests = File('test/fixtures/facts_corpus/tests.dart.txt')
        .readAsStringSync();

    final declarations = decodeFacts(
      encodeFacts(const SyntacticFacts().extract(orders, _a)),
      _a,
    )!.annotatedDeclarations;
    final original = const SyntacticFacts().extract(orders, _a);
    final calls = decodeFacts(
      encodeFacts(const SyntacticFacts().extract(tests, _a)),
      _a,
    )!.testCalls;

    expect(declarations.map((d) => d.name), contains('Order'));
    expect(
      declarations.map((d) => d.tokenHash),
      original.annotatedDeclarations.map((d) => d.tokenHash),
    );
    expect(declarations.first.tokenHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(declarations.first.annotations, ['JsonSerializable']);
    final adds = calls.singleWhere((c) => c.description == 'adds');
    expect(adds.groups, ['cart', 'totals']);
    expect(adds.solo, isNotNull);
    expect(adds.skip, isNotNull, reason: 'the @Skip on the library');
    final subtracts = calls.singleWhere((c) => c.description == 'subtracts');
    expect(subtracts.solo, isNull);
  });

  test('positions are decoded to the same line and column', () {
    final facts = DartFileFacts(
      directives: [
        Directive(
          kind: DirectiveKind.partOf,
          uri: 'x.dart',
          location: Location(_a, const Position(3, 4), const Position(5, 6)),
        ),
      ],
    );

    final decoded = decodeFacts(encodeFacts(facts), RepoPath('c.dart'))!;

    final location = decoded.directives.single.location;
    expect(location.path, RepoPath('c.dart'));
    expect(location.start, const Position(3, 4));
    expect(location.end, const Position(5, 6));
    expect(decoded.directives.single.kind, DirectiveKind.partOf);
    expect(decoded.directives.single.uri, 'x.dart');
  });

  test('a document of another version is not decoded', () {
    final text = encodeFacts(const DartFileFacts());

    expect(decodeFacts(text, _a), isNotNull);
    expect(text, startsWith('{"v":1,'));
    expect(decodeFacts(text.replaceFirst('"v":1', '"v":2'), _a), isNull);
    expect(decodeFacts(text.replaceFirst('"v":1', '"v":"1"'), _a), isNull);
  });

  test('garbage never throws: every strict prefix of a valid document, and '
      'wrongly typed members, decode to null', () {
    final source = File('test/fixtures/facts_corpus/tests.dart.txt')
        .readAsStringSync();
    final text = encodeFacts(const SyntacticFacts().extract(source, _a));

    for (var i = 0; i < text.length; i++) {
      expect(decodeFacts(text.substring(0, i), _a), isNull, reason: '$i');
    }
    for (final garbage in [
      '',
      '{',
      '[]',
      'null',
      '1',
      '"v"',
      '{}',
      '{"v":1}',
      '{"v":1,"directives":"x"}',
      _document(identifiers: 'x'),
      _document(identifiers: [1]),
      _document(isWellFormed: 1),
      _document(directives: [1]),
      _document(directives: [_directive(kind: 'nope')]),
      _document(
        directives: [
          _directive(start: [0, 1]),
        ],
      ),
      _document(
        directives: [
          _directive(start: [1]),
        ],
      ),
      _document(
        directives: [
          _directive(start: [1, 'x']),
        ],
      ),
      _document(directives: [_directive(uri: 3)]),
      _document(annotatedDeclarations: [<String, Object?>{}]),
      _document(testCalls: [<String, Object?>{}]),
    ]) {
      expect(decodeFacts(garbage, _a), isNull, reason: garbage);
    }
  });
}

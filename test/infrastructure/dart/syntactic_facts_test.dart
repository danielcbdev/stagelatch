import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';
import 'package:test/test.dart';

DartFileFacts _extract(String source) =>
    const SyntacticFacts().extract(source, RepoPath('lib/a.dart'));

List<(DirectiveKind, String)> _directives(String source) => [
  for (final d in _extract(source).directives) (d.kind, d.uri),
];

void main() {
  test('extract returns each directive with the location of its URI '
      'literal', () {
    final d = _extract("import 'b.dart';\n").directives.single;

    expect((d.kind, d.uri), (DirectiveKind.import, 'b.dart'));
    expect(
      d.location,
      Location(
        RepoPath('lib/a.dart'),
        const Position(1, 8),
        const Position(1, 16),
      ),
    );
  });

  test('every directive kind, show and hide, prefixes and deferred', () {
    expect(
      _directives(
        'library x;\n'
        "import 'a.dart' as a show A hide B;\n"
        "import 'b.dart' deferred as b;\n"
        "export 'c.dart';\n"
        "part 'd.dart';\n",
      ),
      [
        (DirectiveKind.import, 'a.dart'),
        (DirectiveKind.import, 'b.dart'),
        (DirectiveKind.export, 'c.dart'),
        (DirectiveKind.part, 'd.dart'),
      ],
    );
  });

  test('part of a URI is a partOf directive', () {
    expect(_directives("part of 'lib.dart';\n"), [
      (DirectiveKind.partOf, 'lib.dart'),
    ]);
  });

  test('scanning stops at the first token that does not start a '
      'directive', () {
    expect(
      _directives("import 'a.dart';\nvoid main() {}\nimport 'late.dart';\n"),
      [(DirectiveKind.import, 'a.dart')],
    );
  });

  test('a syntax error after the directives does not hide them', () {
    expect(_directives("import 'a.dart';\nclass {\n"), [
      (DirectiveKind.import, 'a.dart'),
    ]);
  });

  test('library, annotations, a script tag and part of with a library name '
      'produce no URI', () {
    expect(
      _directives(
        '#!/usr/bin/env dart\n'
        "@Deprecated('it\\'s old (really)')\n"
        '@pragma.x\n'
        'library a.b;\n'
        'part of a.b;\n',
      ),
      isEmpty,
    );
  });

  test('directive-like text in comments and strings is ignored', () {
    expect(
      _directives(
        "// import 'x.dart';\n"
        "/* import 'y.dart'; /* nested */ import 'z.dart'; */\n"
        "/// import 'w.dart';\n"
        "import 'real.dart';\n",
      ),
      [(DirectiveKind.import, 'real.dart')],
    );
  });

  test('adjacent string literals are concatenated', () {
    final d = _extract("import 'a' \"/b.dart\";\n").directives.single;

    expect(d.uri, 'a/b.dart');
    expect(d.location.start, const Position(1, 8));
    expect(d.location.end, const Position(1, 21));
  });

  test('a conditional import yields one directive per branch, the condition '
      'string excluded', () {
    expect(
      _directives(
        "import 'stub.dart'\n"
        "    if (dart.library.io) 'io.dart'\n"
        "    if (dart.library.js_interop == 'true') 'web.dart';\n",
      ),
      [
        (DirectiveKind.import, 'stub.dart'),
        (DirectiveKind.import, 'io.dart'),
        (DirectiveKind.import, 'web.dart'),
      ],
    );
  });

  test('raw and triple-quoted strings are read', () {
    expect(_directives("import r'a.dart';\nimport '''b.dart''';\n"), [
      (DirectiveKind.import, 'a.dart'),
      (DirectiveKind.import, 'b.dart'),
    ]);
  });

  test('locations count lines after CRLF and a byte order mark', () {
    final d = _extract("﻿// c\r\nimport 'b.dart';\r\n").directives.single;

    expect(d.location.start, const Position(2, 8));
  });

  test('an unterminated string or comment ends the scan without failing', () {
    expect(_directives("import 'a.dart"), [(DirectiveKind.import, 'a.dart')]);
    expect(_directives("import 'a.dart';\n/* never closed"), [
      (DirectiveKind.import, 'a.dart'),
    ]);
  });

  test('a file without test calls has none, and has its identifiers', () {
    final facts = _extract(
      "import 'a.dart';\n@JsonSerializable() class A {}\n",
    );

    expect(facts.annotatedDeclarations.single.name, 'A');
    expect(facts.isWellFormed, isTrue);
    expect(facts.testCalls, isEmpty);
    expect(facts.identifiers, {'import', 'JsonSerializable', 'class', 'A'});
  });
}

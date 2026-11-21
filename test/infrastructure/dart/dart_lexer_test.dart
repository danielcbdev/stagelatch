import 'package:stagelatch/src/infrastructure/dart/dart_lexer.dart';
import 'package:test/test.dart';

List<String> _tokens(String source) => lex(source).lexemes;

void main() {
  group('tokens', () {
    test('words, numbers and punctuation', () {
      expect(_tokens('int x = 1_000 + 0x1F;'), [
        'int',
        'x',
        '=',
        '1_000',
        '+',
        '0x1F',
        ';',
      ]);
    });

    test('numbers: fractions, exponents, and a dot that is not a fraction', () {
      expect(_tokens('1.5e3 .5 1..a 2.toString() 3e-2'), [
        '1.5e3',
        '.5',
        '1',
        '..',
        'a',
        '2',
        '.',
        'toString',
        '(',
        ')',
        '3e-2',
      ]);
    });

    test('comments and whitespace are not tokens', () {
      expect(
        _tokens(
          '// line\n/* block /* nested */ still */ a /// doc\n'
          '/** doc */ b',
        ),
        ['a', 'b'],
      );
    });

    test('a script tag is skipped', () {
      expect(_tokens('#!/usr/bin/env dart\nvoid main() {}'), [
        'void',
        'main',
        '(',
        ')',
        '{',
        '}',
      ]);
    });

    test('operators use the longest match', () {
      expect(
        _tokens('>>>= >>= >>> >> >= > ?. ?? ??= ?.. ... ...? ~/ ~/= => <<= <='),
        [
          '>>>=',
          '>>=',
          '>>>',
          '>>',
          '>=',
          '>',
          '?.',
          '??',
          '??=',
          '?..',
          '...',
          '...?',
          '~/',
          '~/=',
          '=>',
          '<<=',
          '<=',
        ],
      );
    });

    test('[] and []= are single tokens, [ ] is not', () {
      expect(_tokens('operator []=(a) operator [](a) x[0] = [ ]'), [
        'operator',
        '[]=',
        '(',
        'a',
        ')',
        'operator',
        '[]',
        '(',
        'a',
        ')',
        'x',
        '[',
        '0',
        ']',
        '=',
        '[',
        ']',
      ]);
    });

    test('a word may contain digits, underscores and dollar signs', () {
      expect(_tokens(r'_a1 $b a$c'), ['_a1', r'$b', r'a$c']);
    });
  });

  group('strings', () {
    test('a plain string is one token, escapes included', () {
      expect(
        _tokens(
          r"'it\'s' "
          '"two"',
        ),
        [r"'it\'s'", '"two"'],
      );
    });

    test('an interpolated identifier splits the string at the dollar', () {
      expect(_tokens(r"'a$b c'"), ["'a", r'$', 'b', " c'"]);
    });

    test('an interpolated expression splits it around the braces', () {
      expect(_tokens(r"'a${b + 1}c'"), ["'a", r'${', 'b', '+', '1', '}', "c'"]);
    });

    test('consecutive interpolations leave an empty segment, as the Dart '
        'scanner does', () {
      expect(_tokens(r"'$a$b'"), ["'", r'$', 'a', '', r'$', 'b', "'"]);
    });

    test('interpolations nest', () {
      expect(_tokens(r"'a ${'b ${c}'} d'"), [
        "'a ",
        r'${',
        "'b ",
        r'${',
        'c',
        '}',
        "'",
        '}',
        " d'",
      ]);
    });

    test('a map literal inside an interpolation does not end it', () {
      expect(_tokens(r"'${ {1: 2}[1] }x'"), [
        "'",
        r'${',
        '{',
        '1',
        ':',
        '2',
        '}',
        '[',
        '1',
        ']',
        '}',
        "x'",
      ]);
    });

    test('raw strings and a dollar that does not start an interpolation', () {
      expect(_tokens(r"r'a$b' 'cost: $' '$1'"), [
        r"r'a$b'",
        r"'cost: $'",
        r"'$1'",
      ]);
    });

    test('multi-line strings keep quotes and newlines inside', () {
      expect(_tokens("'''a'b\n\"\"\"c''' x"), ["'''a'b\n\"\"\"c'''", 'x']);
      expect(_tokens('"""a\n"b"\nc""" y'), ['"""a\n"b"\nc"""', 'y']);
    });
  });

  group('balance', () {
    test('a well-formed file is balanced', () {
      final lexed = lex(r"void main() { var a = [1, {2: '${f(3)}'}]; }");

      expect(lexed.balanced, isTrue);
    });

    test('brackets are matched to their closers', () {
      final lexed = lex('f(a[0]) { }');
      final tokens = lexed.lexemes;

      expect(lexed.closerOf(tokens.indexOf('(')), tokens.indexOf(')'));
      expect(lexed.closerOf(tokens.indexOf('[')), tokens.indexOf(']'));
      expect(lexed.closerOf(tokens.indexOf('{')), tokens.indexOf('}'));
      expect(lexed.closerOf(tokens.indexOf('f')), -1);
    });

    test('an interpolation brace is matched to its closer', () {
      final lexed = lex(r"'${a}'");
      final tokens = lexed.lexemes;

      expect(lexed.closerOf(tokens.indexOf(r'${')), tokens.indexOf('}'));
    });

    test('what makes a file not balanced', () {
      expect(lex("'abc").balanced, isFalse, reason: 'unterminated string');
      expect(lex('"""abc').balanced, isFalse, reason: 'unterminated triple');
      expect(lex('a /* b').balanced, isFalse, reason: 'unterminated comment');
      expect(lex('f(a]').balanced, isFalse, reason: 'mismatched bracket');
      expect(lex('a }').balanced, isFalse, reason: 'extra closer');
      expect(lex('{ a').balanced, isFalse, reason: 'unclosed opener');
      expect(
        lex(r"'a ${b").balanced,
        isFalse,
        reason: 'unclosed interpolation',
      );
    });

    test('lexing a broken file never throws', () {
      for (final source in [
        '',
        "'",
        r"'$",
        r"'${",
        '/*',
        '"""',
        '}}}{{{',
        '\u0000￿',
        'r',
        "r'",
      ]) {
        expect(() => lex(source), returnsNormally, reason: source);
      }
    });
  });
}

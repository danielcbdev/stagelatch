import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';
import 'package:test/test.dart';

DartFileFacts _facts(String source) =>
    const SyntacticFacts().extract(source, RepoPath('lib/a.dart'));

Set<String> _ids(String source) => _facts(source).identifiers;

/// A set that holds at least one of [words].
Matcher containsAny(List<String> words) =>
    anyOf([for (final word in words) contains(word)]);

void main() {
  test('identifiers are the words of the code, not of comments or strings', () {
    expect(
      _ids("void f() { l10n.checkoutTitle; } // inComment 'inString'"),
      containsAll(['f', 'l10n', 'checkoutTitle']),
    );
    expect(
      _ids("// inComment\nvar s = 'inString';"),
      isNot(containsAny(['inComment', 'inString'])),
    );
    expect(
      _ids('/* inBlock /* nested */ still */ var x = 1;'),
      allOf(contains('x'), isNot(containsAny(['inBlock', 'nested', 'still']))),
    );
    expect(
      _ids("var s = r'rawText' + '''tripleText''';"),
      isNot(containsAny(['rawText', 'tripleText'])),
    );
  });

  test('keywords are identifiers too (ADR-0017)', () {
    expect(_ids('class Foo {}'), containsAll(['class', 'Foo']));
  });

  test('an identifier inside an interpolation counts', () {
    expect(
      _ids(r"var s = '${l10n.legacyBanner} $other';"),
      containsAll(['l10n', 'legacyBanner', 'other']),
    );
  });

  test('text around an interpolation does not count', () {
    expect(
      _ids(r"var s = 'before ${a} between $b after';"),
      allOf(
        containsAll(['a', 'b']),
        isNot(containsAny(['before', 'between', 'after'])),
      ),
    );
  });

  test('a file that is not well formed has no identifiers', () {
    final facts = _facts("var s = 'unterminated;");

    expect(facts.isWellFormed, isFalse);
    expect(facts.identifiers, isEmpty);
  });

  test('a file with unbalanced brackets has no identifiers', () {
    final facts = _facts('void f() { used;');

    expect(facts.isWellFormed, isFalse);
    expect(facts.identifiers, isEmpty);
  });

  test('an empty file has no identifiers and is well formed', () {
    final facts = _facts('');

    expect(facts.isWellFormed, isTrue);
    expect(facts.identifiers, isEmpty);
  });

  test('identifiers are linear on a hostile 1 MiB file', () {
    const mib = 1024 * 1024;
    final shapes = <String, String>{
      'one identifier': 'a' * mib,
      'distinct identifiers': [for (var i = 0; i < mib ~/ 8; i++) 'id$i']
          .join(' '),
      'nested interpolation': r"'${" * (mib ~/ 4),
      'balanced interpolation words': "var s = '${r'${a}' * (mib ~/ 8)}';",
      'balanced parentheses': '(' * 400000 + ')' * 400000,
    };
    for (final MapEntry(key: name, value: source) in shapes.entries) {
      final watch = Stopwatch()..start();
      expect(_facts(source), isNotNull, reason: name);
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 30)),
        reason: name,
      );
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}

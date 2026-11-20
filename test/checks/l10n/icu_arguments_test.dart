import 'package:stagelatch/src/checks/l10n/icu_arguments.dart';
import 'package:test/test.dart';

void main() {
  test('simple, plural and select arguments, including nested ones', () {
    expect(icuArguments('Hi {name}'), {'name'});
    expect(
      icuArguments('{count, plural, =0{none} other{{count} items for {user}}}'),
      {'count', 'user'},
    );
    expect(
      icuArguments('{gender, select, male{He} other{They}} liked {thing}'),
      {'gender', 'thing'},
    );
  });

  test('quoted text is literal', () {
    expect(icuArguments("Use '{name}' literally"), isEmpty);
    expect(icuArguments("It''s {name}"), {'name'});
  });

  test('a lone apostrophe is text and does not quote', () {
    expect(icuArguments("Don't {name}"), {'name'});
  });

  test('a doubled apostrophe inside a quote is a literal apostrophe', () {
    expect(icuArguments("'{it''s}' {name}"), {'name'});
  });

  test('plural keywords and literal branches are not arguments', () {
    expect(icuArguments('{n, plural, one{one} other{many}}'), {'n'});
    expect(icuArguments('{n, plural, offset:1 =0{none} =1{one} other{many}}'), {
      'n',
    });
  });

  test('select inside plural, and plural inside select', () {
    expect(
      icuArguments(
        '{n, plural, one{{g, select, f{She} other{They}}} other{{n} people}}',
      ),
      {'n', 'g'},
    );
  });

  test('typed arguments are collected by name', () {
    expect(icuArguments('{amount, number, currency} on {when, date, yMd}'), {
      'amount',
      'when',
    });
  });

  test('whitespace around a name is trimmed', () {
    expect(icuArguments('Hi { name }'), {'name'});
  });

  test('unbalanced input returns what was found and never throws', () {
    expect(icuArguments('{name'), {'name'});
    expect(icuArguments('}}{{'), isEmpty);
    expect(icuArguments('{count, plural, one{{x}'), {'count', 'x'});
    expect(icuArguments("'{name"), isEmpty);
  });

  test('the empty message and a message without arguments', () {
    expect(icuArguments(''), isEmpty);
    expect(icuArguments('Hello, world.'), isEmpty);
  });

  group('hostile input (S6)', () {
    const timeout = Timeout(Duration(seconds: 30));
    const mib = 1024 * 1024;

    test('10,000 nested braces complete', () {
      final nested = '{a, plural, other{' * 10000;
      expect(icuArguments(nested), {'a'});
    }, timeout: timeout);

    test('1 MiB of opening braces completes', () {
      expect(icuArguments('{' * mib), isEmpty);
    }, timeout: timeout);

    test('1 MiB of closing braces completes', () {
      expect(icuArguments('}' * mib), isEmpty);
    }, timeout: timeout);

    test('1 MiB of text with one argument completes', () {
      expect(icuArguments('${'a' * mib}{name}'), {'name'});
    }, timeout: timeout);

    test('1 MiB of apostrophes completes', () {
      expect(icuArguments("'" * mib), isEmpty);
      expect(icuArguments("'{" * (mib ~/ 2)), isEmpty);
    }, timeout: timeout);
  });
}

import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

void main() {
  group('RuleId', () {
    test('parses check/rule', () {
      expect(
        RuleId.parse('pubspec/path-dependency'),
        const RuleId('pubspec', 'path-dependency'),
      );
    });

    test('keeps the analyzer spelling of a diagnostic code', () {
      expect(RuleId.parse('analyze/unused_import').rule, 'unused_import');
    });

    test('rejects everything that is not check/rule', () {
      const invalid = [
        '',
        'pubspec',
        '/x',
        'a/',
        'a/b/c',
        'A/b',
        'a/B',
        'a b/c',
        '-a/b',
        'a/_b',
      ];
      for (final value in invalid) {
        expect(
          () => RuleId.parse(value),
          throwsFormatException,
          reason: '"$value" must be rejected',
        );
      }
    });

    test('prints as check/rule', () {
      expect(const RuleId('tests', 'solo').toString(), 'tests/solo');
    });

    test('orders by check, then rule', () {
      final ids = [
        RuleId.parse('pubspec/unpinned-git'),
        RuleId.parse('format/unformatted'),
        RuleId.parse('pubspec/path-dependency'),
      ]..sort();

      expect(ids.map((id) => id.toString()), [
        'format/unformatted',
        'pubspec/path-dependency',
        'pubspec/unpinned-git',
      ]);
    });

    test('is equal to another id with the same parts', () {
      const a = RuleId('tests', 'solo');

      expect(a, RuleId.parse('tests/solo'));
      expect(a.hashCode, RuleId.parse('tests/solo').hashCode);
      expect(a, isNot(const RuleId('tests', 'new-skip')));
      expect(a, isNot(const RuleId('l10n', 'solo')));
    });
  });

  group('RuleDescriptor', () {
    test('is not fixable unless stated', () {
      const descriptor = RuleDescriptor(
        id: RuleId('tests', 'solo'),
        defaultSeverity: Severity.error,
        summary: 'A committed solo test.',
      );

      expect(descriptor.fixable, isFalse);
      expect(descriptor.id, const RuleId('tests', 'solo'));
      expect(descriptor.defaultSeverity, Severity.error);
      expect(descriptor.summary, 'A committed solo test.');
    });
  });

  group('RuleLevel', () {
    test('maps to a severity, except off', () {
      expect(RuleLevel.error.severity, Severity.error);
      expect(RuleLevel.warning.severity, Severity.warning);
      expect(RuleLevel.off.severity, isNull);
    });
  });
}

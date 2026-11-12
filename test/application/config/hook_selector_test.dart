import 'package:stagelatch/src/application/config/hook_selector.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:test/test.dart';

void main() {
  group('HookSelector.parse', () {
    test('a bare name selects a whole check', () {
      final selector = HookSelector.parse('sensitive-files');

      expect(selector.check, 'sensitive-files');
      expect(selector.rule, isNull);
      expect(selector.ruleId, isNull);
    });

    test('check/rule selects one rule', () {
      final selector = HookSelector.parse('tests/solo');

      expect(selector.check, 'tests');
      expect(selector.rule, 'solo');
      expect(selector.ruleId, const RuleId('tests', 'solo'));
    });

    test('rejects anything else', () {
      for (final value in ['', 'a/b/c', 'A', 'a/', '/b', 'a b', 'a/B']) {
        expect(
          () => HookSelector.parse(value),
          throwsFormatException,
          reason: '"$value" must be rejected',
        );
      }
    });
  });

  group('HookSelector', () {
    test('prints as it is written in the config', () {
      expect(HookSelector.parse('pubspec').toString(), 'pubspec');
      expect(HookSelector.parse('tests/solo').toString(), 'tests/solo');
    });

    test('is equal when check and rule are equal', () {
      expect(
        HookSelector.parse('tests/solo'),
        HookSelector.parse('tests/solo'),
      );
      expect(
        HookSelector.parse('tests/solo').hashCode,
        HookSelector.parse('tests/solo').hashCode,
      );
      expect(
        HookSelector.parse('tests'),
        isNot(HookSelector.parse('tests/solo')),
      );
    });
  });
}

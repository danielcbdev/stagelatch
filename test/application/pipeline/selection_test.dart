import 'package:stagelatch/src/application/config/hook_selector.dart';
import 'package:stagelatch/src/application/pipeline/selection.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:test/test.dart';

import '../../support/fake_check.dart';

Selection _selection(List<String> selectors) =>
    Selection.of(selectors.map(HookSelector.parse));

void main() {
  group('Selection', () {
    test('a check selector enables every rule of the check', () {
      final selection = _selection(['pubspec']);

      expect(
        selection.isEnabled(const RuleId('pubspec', 'path-dependency')),
        isTrue,
      );
      expect(
        selection.isEnabled(const RuleId('pubspec', 'unparseable')),
        isTrue,
      );
      expect(selection.isEnabled(const RuleId('tests', 'solo')), isFalse);
    });

    test('a rule selector enables that rule only', () {
      final selection = _selection(['tests/solo']);

      expect(selection.isEnabled(const RuleId('tests', 'solo')), isTrue);
      expect(selection.isEnabled(const RuleId('tests', 'new-skip')), isFalse);
    });

    test('a check selector covers rule names nobody declared', () {
      final selection = _selection(['analyze']);

      expect(
        selection.isEnabled(const RuleId('analyze', 'unused_import')),
        isTrue,
      );
    });

    test('a check runs when it is selected whole or by one rule', () {
      final selection = _selection(['pubspec', 'tests/solo']);

      expect(selection.runs(FakeCheck('pubspec')), isTrue);
      expect(selection.runs(FakeCheck('tests')), isTrue);
      expect(selection.runs(FakeCheck('format')), isFalse);
    });

    test('an empty selection runs nothing', () {
      final selection = _selection([]);

      expect(selection.runs(FakeCheck('pubspec')), isFalse);
      expect(selection.isEnabled(const RuleId('pubspec', 'x')), isFalse);
    });

    test('a whole-check selector wins over a rule selector of that check', () {
      final selection = _selection(['tests/solo', 'tests']);

      expect(selection.isEnabled(const RuleId('tests', 'new-skip')), isTrue);
    });
  });
}

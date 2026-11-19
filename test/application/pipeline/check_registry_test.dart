import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:test/test.dart';

import '../../support/fake_check.dart';

void main() {
  group('CheckRegistry', () {
    final pubspec = FakeCheck('pubspec', rules: ['path-dependency', 'x']);
    final analyze = FakeCheck('analyze', rules: [], hasDynamicRules: true);
    final registry = CheckRegistry([pubspec, analyze]);

    test('keeps checks in the order given', () {
      expect(registry.checks, [pubspec, analyze]);
      expect(() => registry.checks.add(pubspec), throwsUnsupportedError);
    });

    test('answers the catalog queries', () {
      expect(registry.checkIds, {'pubspec', 'analyze'});
      expect(registry.hasRule(const RuleId('pubspec', 'x')), isTrue);
      expect(registry.hasRule(const RuleId('pubspec', 'nope')), isFalse);
      expect(registry.hasRule(const RuleId('analyze', 'anything')), isFalse);
      expect(registry.hasDynamicRules('analyze'), isTrue);
      expect(registry.hasDynamicRules('pubspec'), isFalse);
      expect(registry.hasDynamicRules('unknown'), isFalse);
    });

    test('describes a declared rule, and nothing else', () {
      expect(
        registry.descriptorOf(const RuleId('pubspec', 'x'))?.id,
        const RuleId('pubspec', 'x'),
      );
      expect(registry.descriptorOf(const RuleId('analyze', 'y')), isNull);
    });

    test('rejects two checks with the same id', () {
      expect(
        () => CheckRegistry([FakeCheck('a'), FakeCheck('a')]),
        throwsArgumentError,
      );
    });
  });
}

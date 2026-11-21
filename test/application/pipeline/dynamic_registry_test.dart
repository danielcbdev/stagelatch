import 'package:stagelatch/src/application/custom/external_check.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:test/test.dart';

import '../../support/fake_check.dart';
import '../../support/fake_check_process.dart';

ExternalCheck _external(String id) => ExternalCheck(
  id: id,
  command: const ['dart', 'run', 'tool/x.dart'],
  factory: FakeCheckProcessFactory(),
  timeout: const Duration(seconds: 60),
  sourceClosure: {RepoPath('tool/x.dart')},
  workingDirectory: '/tmp/repo',
);

void main() {
  group('CheckRegistry.withCustom', () {
    test('appends custom checks after the built-ins', () {
      final pubspec = FakeCheck('pubspec', rules: ['path-dependency']);
      final analyze = FakeCheck('analyze', rules: [], hasDynamicRules: true);
      final base = CheckRegistry([pubspec, analyze]);
      final team = _external('team');
      final other = _external('other');

      final registry = base.withCustom([team, other]);

      expect(registry.checks, [pubspec, analyze, team, other]);
      expect(registry.checkIds, {'pubspec', 'analyze', 'team', 'other'});
      expect(registry.hasDynamicRules('team'), isTrue);
      expect(registry.hasDynamicRules('other'), isTrue);
      expect(registry.hasDynamicRules('pubspec'), isFalse);
      expect(registry.hasRule(const RuleId('team', 'anything')), isFalse);
    });

    test('rejects a custom check that shadows a built-in id', () {
      final base = CheckRegistry([FakeCheck('pubspec')]);

      expect(
        () => base.withCustom([_external('pubspec')]),
        throwsArgumentError,
      );
    });

    test('rejects two custom checks with the same id', () {
      final base = CheckRegistry([FakeCheck('format')]);

      expect(
        () => base.withCustom([_external('team'), _external('team')]),
        throwsArgumentError,
      );
    });

    test('an empty custom list returns an equivalent registry', () {
      final pubspec = FakeCheck('pubspec');
      final base = CheckRegistry([pubspec]);

      final registry = base.withCustom(const []);

      expect(registry.checks, [pubspec]);
      expect(identical(registry, base), isFalse);
    });
  });
}

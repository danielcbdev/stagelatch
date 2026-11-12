import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/config/hook_selector.dart';
import 'package:stagelatch/src/application/pipeline/finding_filters.dart';
import 'package:stagelatch/src/application/pipeline/selection.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_check.dart';

void main() {
  final check = FakeCheck('alpha', rules: ['one', 'two', 'three']);

  group('applyLevels', () {
    test('off drops, warning downgrades, error upgrades', () {
      final findings = [
        check.finding('a.dart'),
        check.finding('b.dart', rule: 'two'),
        check.finding('c.dart', rule: 'three', severity: Severity.warning),
      ];

      final result = applyLevels(findings, {
        const RuleId('alpha', 'one'): RuleLevel.off,
        const RuleId('alpha', 'two'): RuleLevel.warning,
        const RuleId('alpha', 'three'): RuleLevel.error,
      });

      expect(result.map((f) => (f.rule.rule, f.severity)), [
        ('two', Severity.warning),
        ('three', Severity.error),
      ]);
    });

    test('a rule without a level keeps the severity it was reported with', () {
      final findings = [
        check.finding('a.dart', severity: Severity.warning),
        check.finding('b.dart', rule: 'two'),
      ];

      expect(applyLevels(findings, const {}), findings);
    });

    test('changes nothing but the severity', () {
      final original = check.finding('a.dart', line: 7, message: 'kept');

      final result = applyLevels(
        [original],
        {const RuleId('alpha', 'one'): RuleLevel.warning},
      ).single;

      expect(result.message, 'kept');
      expect(result.location, original.location);
      expect(result.rule, original.rule);
    });
  });

  group('applyExclude', () {
    Glob glob(String pattern) => Glob(pattern, context: p.posix);

    test('drops findings whose path matches a glob', () {
      final findings = [
        check.finding('lib/generated/a.dart'),
        check.finding('lib/src/b.dart'),
        check.finding('model.g.dart'),
      ];

      final result = applyExclude(findings, [
        glob('lib/generated/**'),
        glob('*.g.dart'),
      ]);

      expect(result.map((f) => f.location.path.value), ['lib/src/b.dart']);
    });

    test('keeps everything without globs', () {
      final findings = [check.finding('a.dart')];

      expect(applyExclude(findings, const []), findings);
    });
  });

  group('applySelection', () {
    test('drops findings of rules the hook did not select', () {
      final selection = Selection.of([HookSelector.parse('alpha/one')]);
      final findings = <Finding>[
        check.finding('a.dart'),
        check.finding('b.dart', rule: 'two'),
      ];

      expect(applySelection(findings, selection), [findings.first]);
    });
  });
}

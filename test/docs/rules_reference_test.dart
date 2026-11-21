import 'dart:io';

import 'package:stagelatch/src/cli/composition.dart';
import 'package:test/test.dart';

import '../../tool/generate_rules_doc.dart';

void main() {
  final text = File(rulesDocPath).readAsStringSync();

  test('docs/rules.md is what the generator writes from the registry', () {
    expect(
      text,
      renderRulesDoc(productionChecks),
      reason: 'Run: $generatorCommand',
    );
  });

  test('the generator command is in the first lines of the file', () {
    final head = text.split('\n').take(3).join('\n');

    expect(head, contains(generatorCommand));
  });

  test('every registered rule is listed exactly once', () {
    for (final check in productionChecks) {
      for (final rule in check.rules) {
        expect(
          '| `${rule.id}` |'.allMatches(text),
          hasLength(1),
          reason: '${rule.id}',
        );
      }
    }
  });

  test('every check has a section, and dynamic rules are explained', () {
    for (final check in productionChecks) {
      expect(text, contains('\n## `${check.id}`\n'));
    }
    expect(text, contains('`analyze/<analyzer code>`'));
  });

  test('uses LF, ends with one newline and mentions the baseline', () {
    expect(text, isNot(contains('\r')));
    expect(text, endsWith('\n'));
    expect(text, isNot(endsWith('\n\n')));
    expect(text, contains('stagelatch baseline create'));
  });
}

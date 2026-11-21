import 'dart:convert';

import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/inline_ignore.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:test/test.dart';

import 'fixtures_path.dart';

void main() {
  test('built-in rule ids match the frozen 1.0 golden list', () {
    final registry = CheckRegistry(productionChecks);
    final actual = <String>{
      for (final check in registry.checks)
        for (final rule in check.rules) rule.id.toString(),
      invalidIgnoreRule.toString(),
    }.toList()..sort();

    final expected = (jsonDecode(
      readCompatFixture('rule_ids.json'),
    ) as List<Object?>).cast<String>();

    expect(actual, expected);
  });
}

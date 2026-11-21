import 'dart:io';

import 'package:stagelatch/src/infrastructure/dart/facts_codec.dart';
import 'package:test/test.dart';

import '../../../tool/facts_corpus.dart';

void main() {
  test('the facts of the fixed corpus equal the golden of this version', () {
    final golden = File(goldenPath(factsFormatVersion));
    expect(
      golden.existsSync(),
      isTrue,
      reason:
          '${golden.path} is missing. Run: dart run tool/update_facts_golden.dart',
    );

    expect(
      renderFactsGolden(),
      golden.readAsStringSync(),
      reason:
          'The facts of the corpus changed. Raise factsFormatVersion, then '
          'run: dart run tool/update_facts_golden.dart',
    );
  });

  test('the golden names the version it was made for', () {
    expect(
      File(goldenPath(factsFormatVersion)).readAsStringSync(),
      contains('"factsFormatVersion": $factsFormatVersion'),
    );
  });

  test('the corpus holds sources that exercise every kind of fact', () {
    final golden = renderFactsGolden();

    expect(golden, contains('"isWellFormed": false'));
    expect(golden, contains('"isWellFormed": true'));
    expect(golden, contains('"kind": "partOf"'));
    expect(golden, contains('"tokenHash"'));
    expect(golden, contains('"solo"'));
    expect(golden, contains('"skip"'));
  });
}

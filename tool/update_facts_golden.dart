/// Regenerates the golden of the facts of the fixed corpus.
///
/// Usage: `dart run tool/update_facts_golden.dart`, after raising
/// `factsFormatVersion` in `lib/src/infrastructure/dart/facts_codec.dart`.
library;

import 'dart:io';

import 'package:stagelatch/src/infrastructure/dart/facts_codec.dart';

import 'facts_corpus.dart';

void main() {
  final golden = File(goldenPath(factsFormatVersion));
  golden.parent.createSync(recursive: true);
  golden.writeAsStringSync(renderFactsGolden());
  stdout.writeln('Wrote ${golden.path}');
}

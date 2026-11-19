/// Applies one scenario to the corpus: `dart run benchmark/bin/apply_scenario.dart s3`.
library;

import 'dart:io';

import 'package:stagelatch_bench/scenario.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: apply_scenario <name>');
    exitCode = 64;
    return;
  }
  await applyScenario(loadScenario(args.single));
  stdout.writeln('Applied ${args.single}.');
}

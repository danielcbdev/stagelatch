/// Applies one scenario to the corpus or a fixture:
/// `dart run benchmark/bin/apply_scenario.dart s3 [old_sdk]`.
library;

import 'dart:io';

import 'package:stagelatch_bench/scenario.dart';
import 'package:stagelatch_bench/workspace.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('Usage: apply_scenario SCENARIO [CORPUS]');
    exitCode = 64;
    return;
  }
  final ws = BenchWorkspace.find(corpus: args.length == 2 ? args[1] : 'corpus');
  await applyScenario(loadScenario(args.first, ws), ws);
  stdout.writeln('Applied ${args.first}.');
}

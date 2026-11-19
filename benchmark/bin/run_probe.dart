/// Runs one probe on one scenario and prints what it saw.
///
/// `dart run benchmark/bin/run_probe.dart PROBE SCENARIO [--no-overlays]
/// [--flutter VERSION] [--cache DIR]`
///
/// Used for the overlay proofs and the in-process phase timings of Tasks 2
/// and 3. The official numbers come from `stagelatch_bench` (Task 6).
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/input.dart';
import 'package:stagelatch_bench/probes.dart';
import 'package:stagelatch_bench/scenario.dart';
import 'package:stagelatch_bench/workspace.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('overlays', defaultsTo: true)
    ..addOption('flutter')
    ..addOption('corpus', defaultsTo: 'corpus')
    ..addOption('cache');
  final args = parser.parse(arguments);
  if (args.rest.length != 2) {
    stderr.writeln(
      'Usage: run_probe <probe> <scenario> [--no-overlays] '
      '[--flutter <version>] [--cache <dir>]',
    );
    exitCode = 64;
    return;
  }
  final ws = BenchWorkspace.find(corpus: args.option('corpus')!);
  final corpus = Corpus.load(ws);
  final probe = probeNamed(
    args.rest[0],
    scratchDir: ws.scratchDir,
    cacheDir: args.option('cache'),
  );
  await applyScenario(loadScenario(args.rest[1], ws), ws);
  var input = await buildProbeInput(
    sdkRoot: Corpus.dartSdk(args.option('flutter') ?? corpus.flutter),
    workspace: ws,
  );
  if (!args.flag('overlays')) input = input.withoutOverlays();

  final result = await probe.run(input);
  final repo = ws.corpusDir;
  stdout.writeln(
    '${probe.name} ${args.rest[1]} '
    'overlays=${input.overlays.length} files=${input.files.length}',
  );
  for (final d in result.diagnostics) {
    stdout.writeln(
      '  ${d.severity.toUpperCase()} ${d.code} '
      '${p.relative(d.path, from: repo)}@${d.offset}+${d.length}: '
      '${d.message}',
    );
  }
  for (final path in input.toFormat) {
    if (result.formatted[path] != readThroughOverlay(input, path)) {
      stdout.writeln('  UNFORMATTED ${p.relative(path, from: repo)}');
    }
  }
  final phases = result.phases.entries
      .map((e) => '${e.key}=${e.value.inMilliseconds}ms')
      .join(' ');
  stdout.writeln('  phases: $phases');
}

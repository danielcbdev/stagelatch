/// The activated executable of the spike: one probe, one run, one line.
///
/// `stagelatch_bench PROBE SCENARIO --cache DIR [--corpus NAME]
/// [--flutter VERSION]`
///
/// Run through `dart pub global activate --source path benchmark`, the
/// distribution path of the real tool (ADR-0004). It does not apply the
/// scenario: `measure.dart` applies it once, then this process does what a
/// gate does on every commit (read the index, build overlays, diagnose,
/// format) and prints one JSON line with the phase timings. The caller
/// measures the whole process from start to exit.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/input.dart';
import 'package:stagelatch_bench/probes.dart';
import 'package:stagelatch_bench/workspace.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('cache', mandatory: true)
    ..addOption('corpus', defaultsTo: 'corpus')
    ..addOption('flutter');
  final args = parser.parse(arguments);
  if (args.rest.length != 2) {
    stderr.writeln('Usage: stagelatch_bench PROBE SCENARIO --cache DIR');
    exitCode = 64;
    return;
  }
  final clock = Stopwatch()..start();
  final ws = BenchWorkspace.find(corpus: args.option('corpus')!);
  final corpus = Corpus.load(ws);
  final input = await buildProbeInput(
    sdkRoot: Corpus.dartSdk(args.option('flutter') ?? corpus.flutter),
    workspace: ws,
  );
  final read = clock.elapsed;
  final probe = probeNamed(
    args.rest[0],
    scratchDir: ws.scratchDir,
    cacheDir: args.option('cache'),
  );
  final result = await probe.run(input);
  stdout.writeln(
    jsonEncode({
      'probe': probe.name,
      'scenario': args.rest[1],
      'phases': {
        'read': read.inMilliseconds,
        for (final MapEntry(:key, :value) in result.phases.entries)
          key: value.inMilliseconds,
      },
      'diagnostics': result.diagnostics.length,
      'inProcessMs': clock.elapsedMilliseconds,
    }),
  );
}

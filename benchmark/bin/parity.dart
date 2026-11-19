/// Compares each probe with the oracle on each scenario.
///
/// `dart run benchmark/bin/parity.dart [--flutter VERSION] [--corpus NAME]
/// [--probe NAME]... [--scenario NAME]...`
///
/// Prints one block per scenario and probe: `parity ok` or one line per
/// difference. Exit code 1 when any difference was found.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/input.dart';
import 'package:stagelatch_bench/oracle.dart';
import 'package:stagelatch_bench/probes.dart';
import 'package:stagelatch_bench/scenario.dart';
import 'package:stagelatch_bench/workspace.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('flutter')
    ..addOption('corpus', defaultsTo: 'corpus')
    ..addMultiOption('probe', defaultsTo: ['embedded', 'delegated'])
    ..addMultiOption('scenario', defaultsTo: ['s3', 's10']);
  final args = parser.parse(arguments);
  final ws = BenchWorkspace.find(corpus: args.option('corpus')!);
  final corpus = Corpus.load(ws);
  final flutter = args.option('flutter') ?? corpus.flutter;
  final sdk = Corpus.dartSdk(flutter);
  final dartVersion = File(p.join(sdk, 'version')).readAsStringSync().trim();
  stdout.writeln('Flutter $flutter, Dart $dartVersion');

  var differences = 0;
  for (final scenario in args.multiOption('scenario')) {
    await applyScenario(loadScenario(scenario, ws), ws);
    final input = await buildProbeInput(sdkRoot: sdk, workspace: ws);
    final expected = await runOracle(input, scratchDir: ws.scratchDir);
    final unformatted = input.toFormat.where(
      (f) => expected.formatted[f] != readThroughOverlay(input, f),
    );
    stdout.writeln(
      '$scenario oracle: ${expected.diagnostics.length} diagnostics, '
      '${unformatted.length} unformatted',
    );
    for (final name in args.multiOption('probe')) {
      final probe = probeNamed(name, scratchDir: ws.scratchDir);
      final actual = await probe.run(input);
      final diff = diffResults(expected, actual);
      differences += diff.length;
      final verdict = diff.isEmpty ? 'parity ok' : '${diff.length} differences';
      stdout.writeln('$scenario $name: $verdict');
      for (final line in diff) {
        stdout.writeln('  ${line.replaceAll('${ws.corpusDir}/', '')}');
      }
    }
  }
  exitCode = differences == 0 ? 0 : 1;
}

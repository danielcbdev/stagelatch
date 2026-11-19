/// Takes the official measurements of plan 00, Task 6.
///
/// `dart run benchmark/bin/measure.dart [--probe NAME]... [--scenario NAME]...
/// [--cold N] [--warm N]`
///
/// For each scenario it applies the scenario once, then for each probe:
/// `--cold` runs, each with a fresh empty cache directory and after one
/// unrelated `dart --version` call; then `--warm` + 1 consecutive runs
/// sharing one cache directory, the first discarded. Every run is the
/// activated `stagelatch_bench` executable, timed from process start to
/// exit. Writes `benchmark/results/06-measurements.json`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/scenario.dart';
import 'package:stagelatch_bench/workspace.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption('probe', defaultsTo: ['embedded', 'delegated'])
    ..addMultiOption('scenario', defaultsTo: ['s3', 's10'])
    ..addOption('cold', defaultsTo: '3')
    ..addOption('warm', defaultsTo: '10')
    ..addOption('out');
  final args = parser.parse(arguments);
  final cold = int.parse(args.option('cold')!);
  final warm = int.parse(args.option('warm')!);
  final ws = BenchWorkspace.find();
  final executable = _activated();
  final results = <Map<String, Object?>>[];

  // The fixed cost of the distribution path: the activated executable
  // started with no arguments prints its usage and exits.
  final startup = <int>[];
  for (var i = 0; i < 10; i++) {
    final clock = Stopwatch()..start();
    await Process.run(executable, const [], workingDirectory: ws.repoRoot);
    startup.add(clock.elapsedMilliseconds);
  }
  stdout.writeln('startup (usage only): $startup ms');

  for (final scenario in args.multiOption('scenario')) {
    await applyScenario(loadScenario(scenario, ws), ws);
    for (final probe in args.multiOption('probe')) {
      final coldRuns = <Map<String, Object?>>[];
      for (var i = 0; i < cold; i++) {
        // An unrelated SDK call first, so the cold run does not also pay
        // for the first `dart` start after the previous block.
        await Process.run('dart', ['--version']);
        final cache = _freshDir(ws, 'cold-$probe-$scenario-$i');
        coldRuns.add(await _timed(executable, probe, scenario, cache, ws));
        stdout.writeln('$scenario $probe cold ${coldRuns.last['totalMs']} ms');
      }
      final cache = _freshDir(ws, 'warm-$probe-$scenario');
      final warmRuns = <Map<String, Object?>>[];
      for (var i = 0; i <= warm; i++) {
        final run = await _timed(executable, probe, scenario, cache, ws);
        // The first run fills the cache: it is a cold run, not a warm one.
        if (i > 0) warmRuns.add(run);
        stdout.writeln(
          '$scenario $probe warm${i == 0 ? ' (discarded)' : ''} '
          '${run['totalMs']} ms',
        );
      }
      results.add({
        'probe': probe,
        'scenario': scenario,
        'cold': coldRuns,
        'warm': warmRuns,
      });
    }
  }
  final report = const JsonEncoder.withIndent('  ').convert({
    'recorded': DateTime.now().toUtc().toIso8601String(),
    'startupMs': startup,
    'results': results,
  });
  final out = File(
    args.option('out') ??
        p.join(ws.benchmarkDir, 'results', '06-measurements.json'),
  )..writeAsStringSync('$report\n');
  stdout.writeln('Wrote ${out.path}');
}

String _activated() {
  final home =
      Platform.environment['PUB_CACHE'] ??
      p.join(Platform.environment['HOME'] ?? '', '.pub-cache');
  final path = p.join(home, 'bin', 'stagelatch_bench');
  if (!File(path).existsSync()) {
    throw StateError('Run: dart pub global activate --source path benchmark');
  }
  return path;
}

String _freshDir(BenchWorkspace ws, String name) {
  final dir = Directory(p.join(ws.scratchDir, 'measure'))
    ..createSync(recursive: true);
  return dir.createTempSync('$name-').path;
}

Future<Map<String, Object?>> _timed(
  String executable,
  String probe,
  String scenario,
  String cache,
  BenchWorkspace ws,
) async {
  final clock = Stopwatch()..start();
  final result = await Process.run(executable, [
    probe,
    scenario,
    '--cache',
    cache,
  ], workingDirectory: ws.repoRoot);
  final total = clock.elapsedMilliseconds;
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      [probe, scenario],
      '${result.stderr}',
      result.exitCode,
    );
  }
  final line = '${result.stdout}'.trim().split('\n').last;
  final json = jsonDecode(line);
  if (json is! Map<String, Object?>) throw FormatException('Bad output', line);
  return {...json, 'totalMs': total};
}

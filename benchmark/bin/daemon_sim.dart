/// Estimates what a persistent analysis server would cost per gate run.
///
/// `dart run benchmark/bin/daemon_sim.dart [SCENARIO] [--iterations N]`
///
/// Starts one server on the corpus package, waits until the whole package
/// is analyzed (what a daemon would have done in the background), then
/// repeats what a warm gate run would ask of it: install the snapshot's
/// overlays, get the errors of the staged files, format them, remove the
/// overlays. Prints the time of each iteration and the server's resident
/// memory. Nothing here is a design; it answers "how fast, how big".
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/input.dart';
import 'package:stagelatch_bench/scenario.dart';
import 'package:stagelatch_bench/server_client.dart';
import 'package:stagelatch_bench/workspace.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()..addOption('iterations', defaultsTo: '10');
  final args = parser.parse(arguments);
  final scenario = args.rest.isEmpty ? 's10' : args.rest.single;
  final iterations = int.parse(args.option('iterations')!);
  final ws = BenchWorkspace.find();
  final corpus = Corpus.load(ws);
  await applyScenario(loadScenario(scenario, ws), ws);
  final input = await buildProbeInput(
    sdkRoot: Corpus.dartSdk(corpus.flutter),
    workspace: ws,
  );
  final cache = Directory(ws.scratchDir).createTempSync('daemon-').path;

  final clock = Stopwatch()..start();
  final server = await ServerClient.start(input.sdkRoot, cacheDir: cache);
  try {
    var started = false;
    final idle = server.notifications.firstWhere((n) {
      if (n case {
        'event': 'server.status',
        'params': {'analysis': {'isAnalyzing': final bool analyzing}},
      }) {
        if (analyzing) started = true;
        return started && !analyzing;
      }
      return false;
    });
    await server.request('server.setSubscriptions', {
      'subscriptions': ['STATUS'],
    });
    await server.request('analysis.setAnalysisRoots', {
      'included': [input.packageRoot],
      'excluded': <String>[],
    });
    await idle;
    stdout.writeln(
      'initial analysis of the package: ${clock.elapsedMilliseconds} ms',
    );

    final times = <int>[];
    for (var i = 0; i < iterations; i++) {
      final run = Stopwatch()..start();
      await server.request('analysis.updateContent', {
        'files': {
          for (final MapEntry(key: path, value: content)
              in input.overlays.entries)
            path: {'type': 'add', 'content': content},
        },
      });
      await server.request('analysis.setPriorityFiles', {'files': input.files});
      final errors = await Future.wait([
        for (final f in input.files)
          server.request('analysis.getErrors', {'file': f}),
      ]);
      for (final f in input.toFormat) {
        await server.request('edit.format', {
          'file': f,
          'selectionOffset': 0,
          'selectionLength': 0,
        });
      }
      await server.request('analysis.updateContent', {
        'files': {
          for (final path in input.overlays.keys) path: {'type': 'remove'},
        },
      });
      times.add(run.elapsedMilliseconds);
      stdout.writeln(
        'iteration $i: ${run.elapsedMilliseconds} ms '
        '(${errors.length} getErrors)',
      );
    }
    times.sort();
    stdout.writeln('p50 ${times[times.length ~/ 2]} ms, max ${times.last} ms');
    final ps = await Process.run('ps', ['-o', 'rss=', '-p', '${server.pid}']);
    final rssKb = int.tryParse('${ps.stdout}'.trim()) ?? 0;
    stdout.writeln('server resident memory: ${rssKb ~/ 1024} MB');
  } finally {
    await server.close();
  }
}

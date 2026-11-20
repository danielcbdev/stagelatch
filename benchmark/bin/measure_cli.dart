/// Measures the real CLI on the spike corpus (plan 02, Task 17, step 1).
///
/// Usage, from `benchmark/`, after `dart pub global activate --source path
/// .` at the repository root:
///
/// `dart run bin/measure_cli.dart [--cold N] [--warm N] [--scope S]`
///
/// For each scenario (`s3`, `s10`) it measures the activated `stagelatch`
/// executable, from process start to exit:
///
/// - `run pre-commit --no-fix` with the default lists (format, pubspec,
///   sensitive-files); `--no-fix` keeps the index identical across runs;
/// - `run pre-push` (analyze) over a commit of the staged scenario, with
///   git's input on stdin.
///
/// Cold runs point `HOME` at a fresh temporary directory, so the analysis
/// server starts with an empty cache; the user's own cache is never touched
/// or deleted. `PUB_CACHE` and `FVM_CACHE_PATH` keep their real values so
/// the executable and the pinned Flutter SDK still resolve. Warm runs use
/// the real environment, the first one discarded.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/proc.dart';
import 'package:stagelatch_bench/scenario.dart';
import 'package:stagelatch_bench/workspace.dart';

Future<void> main(List<String> arguments) async {
  final args =
      (ArgParser()
            ..addOption('cold', defaultsTo: '3')
            ..addOption('warm', defaultsTo: '10')
            ..addOption('scope', help: 'analyze.scope to set; default: none'))
          .parse(arguments);
  final cold = int.parse(args.option('cold')!);
  final warm = int.parse(args.option('warm')!);
  final scope = args.option('scope');
  final ws = BenchWorkspace.find();
  final corpus = Corpus.load(ws);
  final home = Platform.environment['HOME']!;
  final executable = p.join(home, '.pub-cache', 'bin', 'stagelatch');
  if (!File(executable).existsSync()) {
    stderr.writeln('Activate first: dart pub global activate --source path .');
    exitCode = 64;
    return;
  }
  final realEnv = {
    ...Platform.environment,
    'PUB_CACHE':
        Platform.environment['PUB_CACHE'] ?? p.join(home, '.pub-cache'),
    'FVM_CACHE_PATH':
        Platform.environment['FVM_CACHE_PATH'] ?? p.join(home, 'fvm'),
  };

  final results = <Map<String, Object?>>[];
  for (final name in const ['s3', 's10']) {
    final scenario = loadScenario(name, ws);
    for (final hook in const ['pre-commit', 'pre-push']) {
      Future<int> once(Map<String, String> env) async {
        await applyScenario(scenario, ws);
        if (scope != null) {
          // Untracked, so the run reads it from the working tree (with a
          // notice); applyScenario removes it again before the next run.
          await File(p.join(ws.corpusDir, 'stagelatch.yaml'))
              .writeAsString('analyze:\n  scope: $scope\n');
        }
        var input = '';
        if (hook == 'pre-push') {
          // The staged scenario as a commit: pre-push judges commits.
          await run('git', [
            '-c',
            'user.name=bench',
            '-c',
            'user.email=bench@example.invalid',
            'commit',
            '-q',
            '--no-verify',
            '-m',
            'scenario',
          ], workingDirectory: ws.corpusDir);
          final head = (await run('git', [
            'rev-parse',
            'HEAD',
          ], workingDirectory: ws.corpusDir)).trim();
          input = 'refs/heads/bench $head refs/heads/bench ${corpus.sha}\n';
        }
        final watch = Stopwatch()..start();
        final process = await Process.start(
          executable,
          hook == 'pre-push'
              ? ['run', 'pre-push', 'origin', 'bench']
              : ['run', 'pre-commit', '--no-fix'],
          workingDirectory: ws.corpusDir,
          environment: env,
          includeParentEnvironment: false,
        );
        final out = process.stdout.transform(utf8.decoder).join();
        final err = process.stderr.transform(utf8.decoder).join();
        process.stdin.write(input);
        await process.stdin.close();
        final code = await process.exitCode;
        watch.stop();
        final output = await out;
        if (code != 0 && code != 1) {
          stderr.writeln('$name $hook exited $code\n$output\n${await err}');
          exit(70);
        }
        return watch.elapsedMilliseconds;
      }

      final coldMs = <int>[];
      for (var i = 0; i < cold; i++) {
        final temp = await Directory.systemTemp.createTemp('bench_home_');
        try {
          coldMs.add(await once({...realEnv, 'HOME': temp.path}));
        } finally {
          await temp.delete(recursive: true);
        }
        stdout.writeln('$name $hook cold ${coldMs.last} ms');
      }
      final warmMs = <int>[];
      for (var i = 0; i <= warm; i++) {
        final ms = await once(realEnv);
        final note = i == 0 ? ' (discarded)' : '';
        stdout.writeln('$name $hook warm$note $ms ms');
        if (i > 0) warmMs.add(ms);
      }
      results.add({
        'scenario': name,
        'hook': hook,
        'coldMs': coldMs,
        'warmMs': warmMs,
        'cold': _stats(coldMs),
        'warm': _stats(warmMs),
      });
    }
  }
  // Leaves the corpus at its pinned commit.
  await run('git', [
    'reset',
    '-q',
    '--hard',
    corpus.sha,
  ], workingDirectory: ws.corpusDir);

  final name = scope == null ? '17-cli.json' : '17-cli-scope-$scope.json';
  final file = File(p.join(ws.repoRoot, 'benchmark', 'results', name));
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(results)}\n',
  );
  stdout.writeln('Wrote ${file.path}');
}

Map<String, int> _stats(List<int> values) {
  final sorted = [...values]..sort();
  int at(double q) => sorted[((sorted.length - 1) * q).round()];
  return {'p50': at(0.5), 'p95': at(0.95)};
}

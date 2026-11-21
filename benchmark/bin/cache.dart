/// Measures what the facts cache buys (plan 04, Task 1).
///
/// `dart run benchmark/bin/cache.dart [--phase both|cold|warm]`
///
/// Times `CachedFacts.facts` over every `.dart` file of the corpus
/// (`.benchmark/corpus` at the pinned SHA, ADR-0017), one file after the
/// other:
///
/// - `both` (the default): in this process, with no cache at all (the
///   extractor alone), with an empty cache (cold: extract and store), and
///   with the cache the cold run filled (warm: look up and decode); then
///   the same cold and warm runs again in fresh processes, which is how a
///   hook meets the cache. The cache lives in `.benchmark/tmp/cache-bench`.
/// - `cold`: one fresh process; deletes the cache first.
/// - `warm`: one fresh process over what a `cold` run left.
///
/// The last line of a phase is `PHASE <name> <ms> ms, <n> files, <hits>`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:stagelatch/src/infrastructure/dart/cached_facts.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';
import 'package:stagelatch/src/infrastructure/git/git_cli_repository.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:stagelatch/src/infrastructure/io/file_cache.dart';
import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/workspace.dart';

Future<void> main(List<String> args) async {
  final phase = args.length == 2 && args.first == '--phase'
      ? args.last
      : (args.isEmpty ? 'both' : throw ArgumentError('Usage: --phase <p>'));
  final workspace = BenchWorkspace.find();
  final corpus = Corpus.load(workspace);
  final common = p.join(workspace.scratchDir, 'cache-bench');

  final git = GitCliRepository(
    git: GitProcess(
      workingDirectory: workspace.corpusDir,
      environment: Platform.environment,
    ),
  );
  try {
    final files = git.files(CommitSnapshot(corpus.sha));
    final paths = [
      for (final entry in await files.list())
        if (entry.mode.isFile && entry.path.extension == '.dart') entry.path,
    ];
    switch (phase) {
      case 'cold':
        _reset(common);
        await _time('cold', files, paths, FileCache(commonDir: common));
      case 'warm':
        await _time('warm', files, paths, FileCache(commonDir: common));
      case 'both':
        stdout.writeln('${paths.length} .dart files, corpus ${corpus.sha}');
        _reset(common);
        await _time('extract only', files, paths, null);
        await _time(
          'same process, cold',
          files,
          paths,
          FileCache(commonDir: common),
        );
        await _time(
          'same process, warm',
          files,
          paths,
          FileCache(commonDir: common),
        );
        _reset(common);
        await _fresh('cold');
        await _fresh('warm');
      default:
        throw ArgumentError('Unknown phase $phase');
    }
  } finally {
    await git.close();
  }
}

void _reset(String common) {
  final directory = Directory(common);
  if (directory.existsSync()) directory.deleteSync(recursive: true);
  directory.createSync(recursive: true);
}

Future<void> _fresh(String phase) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'run',
    Platform.script.toFilePath(),
    '--phase',
    phase,
  ]);
  if (result.exitCode != 0) {
    throw StateError('phase $phase failed: ${result.stderr}');
  }
  final line = (result.stdout as String)
      .split('\n')
      .lastWhere((l) => l.startsWith('PHASE '));
  stdout.writeln(line.replaceFirst('PHASE ', 'fresh process, '));
}

Future<void> _time(
  String name,
  SnapshotFiles files,
  List<RepoPath> paths,
  FileCache? cache,
) async {
  const extractor = SyntacticFacts();
  final cached = cache == null
      ? null
      : CachedFacts(extractor: extractor, cache: cache);
  // The listing is read; the blobs are fetched by the loop below, as a
  // hook's check would.
  final watch = Stopwatch()..start();
  var wellFormed = 0;
  for (final path in paths) {
    final facts = cached != null
        ? await cached.facts(files, path)
        : switch (await files.readText(path)) {
            final String text => extractor.extract(text, path),
            _ => null,
          };
    if (facts != null && facts.isWellFormed) wellFormed++;
  }
  watch.stop();
  stdout.writeln(
    'PHASE $name ${watch.elapsedMilliseconds} ms, ${paths.length} files, '
    '$wellFormed well formed',
  );
}

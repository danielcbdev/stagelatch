/// Scenarios: a staged change and an unstaged trap applied to the corpus.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/proc.dart';
import 'package:stagelatch_bench/workspace.dart';

/// One scenario under `benchmark/scenarios/<name>/`.
final class Scenario {
  /// Creates a scenario from patch texts.
  const new({
    required this.name,
    required this.stagedPatch,
    required this.unstagedPatch,
  });

  /// Scenario name, also its directory name.
  final String name;

  /// Patch applied to the index only: the snapshot under test.
  final String stagedPatch;

  /// Patch applied to the working tree only: content that must never be
  /// seen by a probe that honours the snapshot.
  final String unstagedPatch;
}

/// Loads the scenario [name] of [workspace].
Scenario loadScenario(String name, [BenchWorkspace? workspace]) {
  final ws = workspace ?? BenchWorkspace.find();
  final dir = p.join(ws.benchmarkDir, 'scenarios', name);
  return Scenario(
    name: name,
    stagedPatch: File(p.join(dir, 'staged.patch')).readAsStringSync(),
    unstagedPatch: File(p.join(dir, 'unstaged.patch')).readAsStringSync(),
  );
}

/// Resets the corpus to the pinned SHA and applies [scenario].
///
/// The staged patch goes to the index only (`git apply --cached`), so the
/// working tree keeps the pinned content for those files; the unstaged
/// patch goes to the working tree only. Every changed path therefore
/// diverges between index and working tree, which is what makes the
/// overlay observable: without it, neither the staged findings nor the
/// absence of the unstaged one can be reproduced.
Future<void> applyScenario(
  Scenario scenario, [
  BenchWorkspace? workspace,
]) async {
  final ws = workspace ?? BenchWorkspace.find();
  final corpus = Corpus.load(ws);
  final dir = ws.corpusDir;
  // --hard: index and working tree back to the pinned commit. Ignored files
  // (.dart_tool/, the pub get output) are kept.
  await run('git', [
    'reset',
    '-q',
    '--hard',
    corpus.sha,
  ], workingDirectory: dir);
  // -f -d without -x: removes untracked files a previous run may have left,
  // never ignored ones.
  await run('git', ['clean', '-q', '-f', '-d'], workingDirectory: dir);
  await run(
    'git',
    ['apply', '--cached', '-'],
    workingDirectory: dir,
    stdin: scenario.stagedPatch,
  );
  await run(
    'git',
    ['apply', '-'],
    workingDirectory: dir,
    stdin: scenario.unstagedPatch,
  );
}

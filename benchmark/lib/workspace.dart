/// Locates the stagelatch checkout and the corpus inside it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The directories the spike works in.
final class BenchWorkspace {
  /// Creates a workspace rooted at [repoRoot].
  const new(this.repoRoot, {this.corpus = 'corpus'});

  /// Finds the stagelatch checkout by walking up from [start] until a
  /// directory contains `benchmark/corpus.yaml`.
  ///
  /// Throws a [StateError] when no such directory exists, so a run from the
  /// wrong place fails before touching any repository.
  ///
  /// [corpus] selects what the scenarios run on: `corpus` (the pinned app
  /// of `corpus.yaml`) or the name of a fixture under `fixtures/`.
  factory find({String? start, String corpus = 'corpus'}) {
    var dir = p.absolute(start ?? Directory.current.path);
    while (true) {
      if (File(p.join(dir, 'benchmark', 'corpus.yaml')).existsSync()) {
        return BenchWorkspace(dir, corpus: corpus);
      }
      final parent = p.dirname(dir);
      if (parent == dir) {
        throw StateError(
          'Run from inside the stagelatch checkout: no benchmark/corpus.yaml '
          'above ${start ?? Directory.current.path}.',
        );
      }
      dir = parent;
    }
  }

  /// Absolute path of the stagelatch checkout.
  final String repoRoot;

  /// The spike package.
  String get benchmarkDir => p.join(repoRoot, 'benchmark');

  /// `corpus`, or the name of a fixture under `benchmark/fixtures/`.
  final String corpus;

  bool get _isFixture => corpus != 'corpus';

  /// The description of the corpus: `corpus.yaml`.
  String get corpusFile => _isFixture
      ? p.join(benchmarkDir, 'fixtures', corpus, 'corpus.yaml')
      : p.join(benchmarkDir, 'corpus.yaml');

  /// The directory of the scenarios of this corpus.
  String get scenariosDir => _isFixture
      ? p.join(benchmarkDir, 'fixtures', corpus, 'scenarios')
      : p.join(benchmarkDir, 'scenarios');

  /// The corpus checkout, ignored by git.
  String get corpusDir => p.join(repoRoot, '.benchmark', corpus);

  /// Scratch space for caches and exported trees, ignored by git.
  String get scratchDir => p.join(repoRoot, '.benchmark', 'tmp');
}

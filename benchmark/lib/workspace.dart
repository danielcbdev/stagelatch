/// Locates the stagelatch checkout and the corpus inside it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The directories the spike works in.
final class BenchWorkspace {
  /// Creates a workspace rooted at [repoRoot].
  const new(this.repoRoot);

  /// Finds the stagelatch checkout by walking up from [start] until a
  /// directory contains `benchmark/corpus.yaml`.
  ///
  /// Throws a [StateError] when no such directory exists, so a run from the
  /// wrong place fails before touching any repository.
  factory find([String? start]) {
    var dir = p.absolute(start ?? Directory.current.path);
    while (true) {
      if (File(p.join(dir, 'benchmark', 'corpus.yaml')).existsSync()) {
        return BenchWorkspace(dir);
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

  /// The corpus checkout, ignored by git.
  String get corpusDir => p.join(repoRoot, '.benchmark', 'corpus');

  /// Scratch space for caches and exported trees, ignored by git.
  String get scratchDir => p.join(repoRoot, '.benchmark', 'tmp');
}

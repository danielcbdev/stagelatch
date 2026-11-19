/// Which Dart files of the snapshot depend on which
/// (docs/specs/dart-toolchain.md, section 3).
library;

import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// The import graph of the repository's Dart files.
///
/// A file depends on every file it names in an `import`, `export`, `part`
/// or `part of` directive. `part` and `part of` make a library and its
/// part depend on each other: they are one library. URIs of `dart:`,
/// other schemes and packages outside the repository are ignored.
final class ImportGraph {
  /// Builds the graph from the [directives] of each file.
  ///
  /// An edge is kept even when its target is not a key of [directives], so
  /// that the importers of a deleted file can still be found.
  factory build({
    required Map<RepoPath, List<Directive>> directives,
    required PackageMap packages,
  }) {
    final reverse = <RepoPath, Set<RepoPath>>{};
    for (final MapEntry(key: file, value: list) in directives.entries) {
      for (final directive in list) {
        final target = _resolve(directive.uri, file, packages);
        if (target == null || target == file) continue;
        (reverse[target] ??= {}).add(file);
      }
    }
    return ImportGraph._({
      for (final MapEntry(:key, :value) in reverse.entries)
        key: [...value]..sort(),
    });
  }

  const new _(this._dependents);

  /// The direct dependents of each file, sorted.
  final Map<RepoPath, List<RepoPath>> _dependents;

  /// [files] and every file that depends on one of them, directly or
  /// transitively, sorted by path.
  Set<RepoPath> dependentsOf(Set<RepoPath> files) {
    final seen = <RepoPath>{...files};
    final pending = [...files];
    while (pending.isNotEmpty) {
      final file = pending.removeLast();
      for (final dependent in _dependents[file] ?? const <RepoPath>[]) {
        if (seen.add(dependent)) pending.add(dependent);
      }
    }
    return {
      ...[...seen]..sort(),
    };
  }

  /// The shortest chain from [from] to [to] following dependents: [from],
  /// a file that depends on it, and so on up to [to]. Breadth-first with
  /// dependents in path order, so ties always resolve the same way. Null
  /// when [to] does not depend on [from].
  List<RepoPath>? shortestChain(RepoPath from, RepoPath to) {
    final previous = <RepoPath, RepoPath?>{from: null};
    var frontier = [from];
    while (frontier.isNotEmpty) {
      final next = <RepoPath>[];
      for (final file in frontier) {
        if (file == to) {
          final chain = <RepoPath>[];
          for (RepoPath? at = to; at != null; at = previous[at]) {
            chain.add(at);
          }
          return chain.reversed.toList();
        }
        for (final dependent in _dependents[file] ?? const <RepoPath>[]) {
          if (previous.containsKey(dependent)) continue;
          previous[dependent] = file;
          next.add(dependent);
        }
      }
      frontier = next;
    }
    return null;
  }

  /// The repository path [uri] names from [file], or null when it names
  /// nothing in this repository.
  static RepoPath? _resolve(String uri, RepoPath file, PackageMap packages) {
    final Uri parsed;
    try {
      parsed = Uri.parse(uri);
    } on FormatException {
      return null;
    }
    final List<String> segments;
    if (parsed.scheme == 'package') {
      final parts = parsed.pathSegments;
      if (parts.length < 2 || parts.first.isEmpty) return null;
      final package = _packageNamed(parts.first, packages);
      if (package == null) return null;
      segments = [...?package.root?.value.split('/'), 'lib', ...parts.skip(1)];
    } else if (parsed.scheme.isEmpty && !parsed.path.startsWith('/')) {
      segments = [...?file.parent?.value.split('/'), ...parsed.pathSegments];
    } else {
      return null;
    }
    final normalized = <String>[];
    for (final segment in segments) {
      if (segment == '.' || segment.isEmpty) continue;
      if (segment == '..') {
        if (normalized.isEmpty) return null;
        normalized.removeLast();
      } else {
        normalized.add(segment);
      }
    }
    if (normalized.isEmpty) return null;
    try {
      return RepoPath(normalized.join('/'));
    } on FormatException {
      return null;
    }
  }

  static DartPackage? _packageNamed(String name, PackageMap packages) {
    for (final package in packages.packages) {
      if (package.name == name) return package;
    }
    return null;
  }
}

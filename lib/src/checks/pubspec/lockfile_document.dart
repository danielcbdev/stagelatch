/// A parsed `pubspec.lock`, seen through the questions rules ask of it.
library;

import 'package:stagelatch/src/domain/documents.dart';

/// One package of a `pubspec.lock`.
final class LockedPackage {
  /// Creates a locked package.
  const new({
    required this.version,
    required this.source,
    required this.dependencyKind,
  });

  /// The resolved version, as written.
  final String version;

  /// Where the package comes from: `hosted`, `git`, `path` or `sdk`.
  final String source;

  /// How the project depends on it, as `pub` writes it: `direct main`,
  /// `direct dev`, `direct overridden` or `transitive`.
  final String dependencyKind;
}

/// A `pubspec.lock` whose root is a map.
///
/// Like `PubspecDocument`, it never throws on an unexpected shape: an entry
/// that lacks a version, a source or a dependency kind is left out, because
/// judging a malformed lock is `pub`'s job, not a rule's.
final class LockfileDocument {
  /// Reads the packages of the lock whose root map is [root].
  new(LocatedMap root) : packages = _read(root);

  /// The locked packages by name, in document order.
  final Map<String, LockedPackage> packages;

  static Map<String, LockedPackage> _read(LocatedMap root) {
    final result = <String, LockedPackage>{};
    if (root.entries['packages']?.value case LocatedMap(:final entries)) {
      for (final MapEntry(:key, :value) in entries.entries) {
        if (value.value case LocatedMap(entries: final fields)) {
          final version = _text(fields['version']);
          final source = _text(fields['source']);
          final kind = _text(fields['dependency']);
          if (version != null && source != null && kind != null) {
            result[key] = LockedPackage(
              version: version,
              source: source,
              dependencyKind: kind,
            );
          }
        }
      }
    }
    return Map.unmodifiable(result);
  }

  static String? _text(LocatedEntry? entry) => switch (entry?.value) {
    LocatedScalar(value: final String text) => text,
    _ => null,
  };
}

/// A parsed `pubspec.yaml`, seen through the questions rules ask of it.
library;

import 'package:stagelatch/src/domain/documents.dart';

/// One entry of a dependency section.
final class DependencyEntry {
  /// Creates an entry.
  const new({required this.name, required this.section, required this.entry});

  /// The package name: the key of the entry.
  final String name;

  /// The section it was declared in: `dependencies` or `dev_dependencies`.
  final String section;

  /// The key and value as written, with their locations.
  final LocatedEntry entry;

  /// The entry named [key] of this dependency's description, such as
  /// `path` or `git`, or null when the dependency is written as a plain
  /// version constraint or has no such key.
  LocatedEntry? field(String key) => switch (entry.value) {
    LocatedMap(:final entries) => entries[key],
    _ => null,
  };
}

/// A `pubspec.yaml` whose root is a map.
///
/// It never throws on an unexpected shape: a section that is missing,
/// empty or not a map simply has no entries. Deciding whether a pubspec is
/// well-formed is pub's job, not a rule's.
final class PubspecDocument {
  /// Wraps the root map of a parsed pubspec.
  const new(this.root);

  /// The name of the section for packages needed at run time.
  static const String dependenciesKey = 'dependencies';

  /// The name of the section for packages needed only during development.
  static const String devDependenciesKey = 'dev_dependencies';

  /// The name of the section that replaces resolved dependencies.
  static const String overridesKey = 'dependency_overrides';

  /// The top-level map of the file.
  final LocatedMap root;

  /// The declared dependencies, in document order; with [includeDev], the
  /// `dev_dependencies` follow the `dependencies`.
  ///
  /// `dependency_overrides` are never included; see [overrides].
  Iterable<DependencyEntry> dependencies({required bool includeDev}) sync* {
    final sections = [dependenciesKey, if (includeDev) devDependenciesKey];
    for (final section in sections) {
      for (final MapEntry(:key, :value) in _section(section).entries) {
        yield DependencyEntry(name: key, section: section, entry: value);
      }
    }
  }

  /// The `dependency_overrides` entry of the root, or null when the file
  /// has none.
  LocatedEntry? get overrides => root.entries[overridesKey];

  /// The names under `dependency_overrides`; empty when the section is
  /// missing, empty or not a map.
  Iterable<String> get overrideNames => _section(overridesKey).keys;

  Map<String, LocatedEntry> _section(String key) =>
      switch (root.entries[key]?.value) {
        LocatedMap(:final entries) => entries,
        _ => const {},
      };
}

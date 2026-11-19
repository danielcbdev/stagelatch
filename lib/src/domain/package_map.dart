/// The Dart packages of a repository and which files belong to each.
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// A Dart package of the repository: a directory with a `pubspec.yaml`.
@immutable
final class DartPackage {
  /// Creates a package rooted at [root].
  const new({required this.root, required this.name, this.usesFlutter = false});

  /// The directory that holds `pubspec.yaml`, or null when that is the
  /// repository root.
  final RepoPath? root;

  /// The `name` of the pubspec.
  final String name;

  /// Whether the package depends on the Flutter SDK.
  final bool usesFlutter;

  @override
  bool operator ==(Object other) =>
      other is DartPackage &&
      other.root == root &&
      other.name == name &&
      other.usesFlutter == usesFlutter;

  @override
  int get hashCode => Object.hash(root, name, usesFlutter);

  @override
  String toString() => 'DartPackage($name at ${root ?? '.'})';
}

/// Assigns each file to the package with the nearest enclosing pubspec.
final class PackageMap {
  /// Creates a map of [packages], in any order.
  ///
  /// Throws [ArgumentError] when two packages share a root.
  factory(Iterable<DartPackage> packages) {
    final sorted = [...packages]..sort((a, b) => _key(a).compareTo(_key(b)));
    final byRoot = {for (final package in sorted) _key(package): package};
    if (byRoot.length != sorted.length) {
      throw ArgumentError('Two packages have the same root.');
    }
    return PackageMap._(List.unmodifiable(sorted), byRoot);
  }

  const new _(this.packages, this._byRoot);

  /// Every package, sorted by root, the repository root first. Unmodifiable.
  final List<DartPackage> packages;

  /// Packages by root directory; `''` stands for the repository root.
  final Map<String, DartPackage> _byRoot;

  static String _key(DartPackage package) => package.root?.value ?? '';

  /// The package [path] belongs to: the one with the deepest root that
  /// contains it. Null when no package contains it.
  DartPackage? packageOf(RepoPath path) {
    for (var dir = path.parent; dir != null; dir = dir.parent) {
      final package = _byRoot[dir.value];
      if (package != null) return package;
    }
    return _byRoot[''];
  }
}

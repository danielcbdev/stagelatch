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
  /// [workspaceRoots] maps each member of a pub workspace to its workspace
  /// root (0.3.0). Throws [ArgumentError] when two packages share a root.
  factory(
    Iterable<DartPackage> packages, {
    Map<DartPackage, DartPackage> workspaceRoots = const {},
  }) {
    final sorted = [...packages]..sort((a, b) => _key(a).compareTo(_key(b)));
    final byRoot = {for (final package in sorted) _key(package): package};
    if (byRoot.length != sorted.length) {
      throw ArgumentError('Two packages have the same root.');
    }
    return PackageMap._(
      List.unmodifiable(sorted),
      byRoot,
      Map.unmodifiable(workspaceRoots),
    );
  }

  const new _(this.packages, this._byRoot, this.workspaceRoots);

  /// Every package, sorted by root, the repository root first. Unmodifiable.
  final List<DartPackage> packages;

  /// Packages by root directory; `''` stands for the repository root.
  final Map<String, DartPackage> _byRoot;

  /// Each workspace member to the package that lists it under `workspace:`.
  final Map<DartPackage, DartPackage> workspaceRoots;

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

  /// The workspace root of a member, or [package] itself.
  DartPackage resolutionPackageOf(DartPackage package) =>
      workspaceRoots[package] ?? package;

  /// The directory that holds [package]'s `pubspec.lock` and
  /// `.dart_tool/package_config.json`: the workspace root for a member,
  /// otherwise [package]'s own root. Null at the repository root.
  RepoPath? resolutionRootOf(DartPackage package) =>
      resolutionPackageOf(package).root;

  /// Every package that resolves at the same root as [package], the root
  /// included, sorted by root. Outside a workspace: just [package].
  List<DartPackage> workspaceMembersOf(DartPackage package) {
    final root = resolutionPackageOf(package);
    final members = [
      root,
      for (final MapEntry(:key, :value) in workspaceRoots.entries)
        if (value == root) key,
    ]..sort((a, b) => _key(a).compareTo(_key(b)));
    return List.unmodifiable(members);
  }
}

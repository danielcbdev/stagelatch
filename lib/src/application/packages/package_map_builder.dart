/// Finds the Dart packages of a snapshot (docs/specs/dart-toolchain.md,
/// section 2).
library;

import 'package:glob/glob.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// Every regular `pubspec.yaml` of [snapshot] defines a package rooted at
/// its directory.
///
/// A pubspec that does not parse, or has no string `name`, still defines a
/// package, with an empty name: its files still belong to it, and no
/// `package:` URI resolves to it. The directory name is not used because
/// it depends on where the repository was cloned (ADR-0003).
///
/// From 0.3.0, packages that declare `resolution: workspace` and are listed
/// by a nearer enclosing pubspec's `workspace:` entries are mapped to that
/// root in [PackageMap.workspaceRoots].
Future<PackageMap> buildPackageMap(
  SnapshotFiles snapshot,
  Documents documents,
) async {
  final packages = <DartPackage>[];
  final maps = <DartPackage, LocatedMap?>{};
  for (final entry in await snapshot.list()) {
    if (entry.path.basename != 'pubspec.yaml' || !entry.mode.isFile) continue;
    final root = entry.path.parent;
    final document = await documents.yaml(snapshot, entry.path);
    final map = switch (document) {
      DocumentParsed(root: final LocatedMap map) => map,
      _ => null,
    };
    final package = DartPackage(
      root: root,
      name: switch (map?.entries['name']?.value) {
        LocatedScalar(value: final String name) => name,
        _ => '',
      },
      usesFlutter: map != null && _usesFlutter(map),
    );
    packages.add(package);
    maps[package] = map;
  }

  final byRoot = {for (final package in packages) _rootKey(package): package};
  final workspaceRoots = <DartPackage, DartPackage>{};
  for (final package in packages) {
    final map = maps[package];
    if (map == null || !_hasWorkspaceResolution(map)) continue;
    final root = _nearestWorkspaceRoot(package, byRoot, maps);
    if (root != null) workspaceRoots[package] = root;
  }

  return PackageMap(packages, workspaceRoots: workspaceRoots);
}

/// Whether a dependency of [pubspec] is `sdk: flutter`, in `dependencies`
/// or `dev_dependencies`.
bool _usesFlutter(LocatedMap pubspec) {
  for (final section in const ['dependencies', 'dev_dependencies']) {
    final dependencies = pubspec.entries[section]?.value;
    if (dependencies is! LocatedMap) continue;
    for (final dependency in dependencies.entries.values) {
      final spec = dependency.value;
      if (spec is! LocatedMap) continue;
      final sdk = spec.entries['sdk']?.value;
      if (sdk is LocatedScalar && sdk.value == 'flutter') return true;
    }
  }
  return false;
}

bool _hasWorkspaceResolution(LocatedMap pubspec) {
  final resolution = pubspec.entries['resolution']?.value;
  return resolution is LocatedScalar && resolution.value == 'workspace';
}

/// The nearest enclosing package that lists [member] under `workspace:`.
DartPackage? _nearestWorkspaceRoot(
  DartPackage member,
  Map<String, DartPackage> byRoot,
  Map<DartPackage, LocatedMap?> maps,
) {
  final memberKey = _rootKey(member);
  var dir = member.root?.parent;
  while (true) {
    final candidate = byRoot[dir == null ? '' : dir.value];
    if (candidate != null) {
      final map = maps[candidate];
      if (map != null &&
          _listsMember(map, candidateRoot: dir, memberKey: memberKey)) {
        return candidate;
      }
    }
    if (dir == null) return null;
    dir = dir.parent;
  }
}

/// Whether [pubspec] lists [memberKey] as a workspace entry relative to
/// [candidateRoot].
bool _listsMember(
  LocatedMap pubspec, {
  required RepoPath? candidateRoot,
  required String memberKey,
}) {
  final workspace = pubspec.entries['workspace']?.value;
  if (workspace is! LocatedList) return false;
  final relative = _relativeTo(candidateRoot, memberKey);
  if (relative == null) return false;
  final allowGlobs = _languageVersionAtLeast(pubspec, 3, 11);
  for (final entry in workspace.items) {
    if (entry is! LocatedScalar) continue;
    final pattern = entry.value;
    if (pattern is! String || pattern.isEmpty) continue;
    if (pattern == relative) return true;
    if (allowGlobs && _isGlob(pattern) && Glob(pattern).matches(relative)) {
      return true;
    }
  }
  return false;
}

/// Path of [memberKey] relative to [root], or null when it is not under it.
String? _relativeTo(RepoPath? root, String memberKey) {
  if (root == null) return memberKey.isEmpty ? null : memberKey;
  if (memberKey == root.value) return null;
  if (!memberKey.startsWith('${root.value}/')) return null;
  return memberKey.substring(root.value.length + 1);
}

bool _isGlob(String pattern) =>
    pattern.contains('*') || pattern.contains('?') || pattern.contains('[');

/// Whether the language version implied by `environment.sdk` is at least
/// [major].[minor].
bool _languageVersionAtLeast(LocatedMap pubspec, int major, int minor) {
  final environment = pubspec.entries['environment']?.value;
  if (environment is! LocatedMap) return false;
  final sdk = environment.entries['sdk']?.value;
  if (sdk is! LocatedScalar) return false;
  final text = sdk.value;
  if (text is! String) return false;
  try {
    final constraint = VersionConstraint.parse(text);
    final floor = Version(major, minor, 0);
    return _minAllows(constraint, floor);
  } on FormatException {
    return false;
  }
}

/// True when every version the constraint allows is >= [floor], or when it
/// allows [floor] itself (caret / range with that lower bound).
bool _minAllows(VersionConstraint constraint, Version floor) {
  if (constraint.allows(floor)) return true;
  if (constraint is VersionRange) {
    final min = constraint.min;
    if (min == null) return false;
    return min >= floor;
  }
  if (constraint is Version) return constraint >= floor;
  return false;
}

String _rootKey(DartPackage package) => package.root?.value ?? '';

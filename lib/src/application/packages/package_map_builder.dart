/// Finds the Dart packages of a snapshot (docs/specs/dart-toolchain.md,
/// section 2).
library;

import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// Every regular `pubspec.yaml` of [snapshot] defines a package rooted at
/// its directory.
///
/// A pubspec that does not parse, or has no string `name`, still defines a
/// package, with an empty name: its files still belong to it, and no
/// `package:` URI resolves to it. The directory name is not used because
/// it depends on where the repository was cloned (ADR-0003).
Future<PackageMap> buildPackageMap(
  SnapshotFiles snapshot,
  Documents documents,
) async {
  final packages = <DartPackage>[];
  for (final entry in await snapshot.list()) {
    if (entry.path.basename != 'pubspec.yaml' || !entry.mode.isFile) continue;
    final root = entry.path.parent;
    final document = await documents.yaml(snapshot, entry.path);
    final map = switch (document) {
      DocumentParsed(root: final LocatedMap map) => map,
      _ => null,
    };
    packages.add(
      DartPackage(
        root: root,
        name: switch (map?.entries['name']?.value) {
          LocatedScalar(value: final String name) => name,
          _ => '',
        },
        usesFlutter: map != null && _usesFlutter(map),
      ),
    );
  }
  return PackageMap(packages);
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

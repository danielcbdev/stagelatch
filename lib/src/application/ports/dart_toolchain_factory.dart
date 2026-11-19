/// How the pipeline obtains a Dart toolchain (ADR-0008,
/// docs/specs/dart-toolchain.md, section 7).
library;

import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// Creates toolchains bound to one snapshot view.
abstract interface class DartToolchainFactory {
  /// A toolchain that answers for [snapshot], using [sdk], for the
  /// repository at [repoRoot] with [packages].
  ///
  /// Creating starts no process and writes no file: that happens on the
  /// first request that needs it.
  DartToolchain create({
    required ResolvedSdk sdk,
    required String repoRoot,
    required SnapshotFiles snapshot,
    required PackageMap packages,
  });
}

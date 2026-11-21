import 'package:stagelatch/src/application/ports/dart_toolchain_factory.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

import 'fake_dart_toolchain.dart';

/// A [DartToolchainFactory] that hands out [FakeDartToolchain]s and records
/// what each was created for.
final class FakeDartToolchainFactory implements DartToolchainFactory {
  /// Creates a factory; [build] makes each toolchain, by default an empty
  /// [FakeDartToolchain].
  new({FakeDartToolchain Function()? build})
    : _build = build ?? FakeDartToolchain.new;

  final FakeDartToolchain Function() _build;

  /// Every toolchain created, in order.
  final List<FakeDartToolchain> created = [];

  /// The snapshot each toolchain was created for, in order.
  final List<SnapshotFiles> snapshots = [];

  /// The test functions each toolchain was created with, in order.
  final List<Set<String>> testFunctions = [];

  /// How many toolchains were created.
  int get createCount => created.length;

  @override
  DartToolchain create({
    required ResolvedSdk sdk,
    required String repoRoot,
    required SnapshotFiles snapshot,
    required PackageMap packages,
    required Set<String> testFunctions,
  }) {
    snapshots.add(snapshot);
    this.testFunctions.add(testFunctions);
    final toolchain = _build();
    created.add(toolchain);
    return toolchain;
  }
}

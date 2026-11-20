/// Finds the Dart SDK the project uses (ADR-0008,
/// docs/specs/dart-toolchain.md, section 1).
library;

import 'package:stagelatch/src/application/config/config.dart';

/// Where a [ResolvedSdk] came from, in the order they are tried.
enum SdkSource {
  /// `sdk_path` in `stagelatch.yaml`.
  sdkPath,

  /// FVM: `.fvm/flutter_sdk`, or the version `.fvmrc` names.
  fvm,

  /// The first `dart` on `PATH`.
  path,
}

/// A Dart SDK outside the repository, ready to run.
final class ResolvedSdk {
  /// Creates a resolved SDK.
  const new({
    required this.root,
    required this.dartExecutable,
    required this.flutterExecutable,
    required this.version,
    required this.source,
  });

  /// The Dart SDK root: the directory with `version` and `bin/dart`. For a
  /// Flutter SDK, its `bin/cache/dart-sdk`.
  final String root;

  /// The `dart` executable of [root].
  final String dartExecutable;

  /// The `flutter` executable when the SDK is a Flutter SDK, else null.
  final String? flutterExecutable;

  /// The first token of the Dart SDK's `version` file, e.g. `3.13.7`.
  final String version;

  /// Which source matched.
  final SdkSource source;
}

/// Resolves the SDK for a run.
abstract interface class SdkLocator {
  /// The SDK [config] and the repository point at.
  ///
  /// Throws `ConfigException` when a configured source does not resolve,
  /// when nothing is found, or when the SDK is inside the repository.
  Future<ResolvedSdk> locate(Config config);
}

/// The pinned corpus described by `benchmark/corpus.yaml`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/workspace.dart';
import 'package:yaml/yaml.dart';

/// Identity of the corpus: where it comes from and how it is resolved.
final class Corpus {
  /// Creates a corpus description.
  const new({
    required this.repository,
    required this.sha,
    required this.packageDir,
    required this.flutter,
  });

  /// Reads `corpus.yaml` of [workspace].
  factory load(BenchWorkspace workspace) {
    final file = File(p.join(workspace.benchmarkDir, 'corpus.yaml'));
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml case {
      'repository': final String repository,
      'sha': final String sha,
      'package_dir': final String packageDir,
      'flutter': final String flutter,
    }) {
      return Corpus(
        repository: repository,
        sha: sha,
        packageDir: packageDir,
        flutter: flutter,
      );
    }
    throw FormatException('Unexpected shape of ${file.path}.');
  }

  /// Clone URL.
  final String repository;

  /// Full commit SHA every scenario starts from.
  final String sha;

  /// Repository-relative directory of the analyzed package.
  final String packageDir;

  /// Flutter version used for `pub get` and as the default SDK.
  final String flutter;

  /// Root of the Flutter SDK [version] installed by FVM.
  ///
  /// FVM keeps versions under `$FVM_CACHE_PATH/versions`, defaulting to
  /// `~/fvm/versions` (the same rule as `specs/dart-toolchain.md` section 1).
  static String flutterSdk(String version) {
    final env = Platform.environment;
    final cache = env['FVM_CACHE_PATH'] ?? p.join(env['HOME'] ?? '', 'fvm');
    return p.join(cache, 'versions', version);
  }

  /// The Dart SDK bundled inside the Flutter SDK [version].
  static String dartSdk(String version) =>
      p.join(flutterSdk(version), 'bin', 'cache', 'dart-sdk');
}

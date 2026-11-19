/// What `doctor` needs from the machine that only infrastructure can see.
library;

import 'package:stagelatch/src/domain/repo_path.dart';

/// Read-only questions about the environment (docs/specs/cli.md, 3.6).
abstract interface class DoctorProbes {
  /// The first line of `git --version`, or null when git cannot be run.
  Future<String?> gitVersion();

  /// The absolute path [name] resolves to on `PATH`, or null.
  Future<String?> resolveOnPath(String name);

  /// Whether `stagelatch` is activated with `dart pub global activate`.
  Future<bool> globallyActivated();

  /// Whether the package at [packageRoot] (null: the repository root) has
  /// a `.dart_tool/package_config.json` in the working tree.
  Future<bool> packageConfigExists(RepoPath? packageRoot);
}

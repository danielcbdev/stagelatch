/// The only place that constructs infrastructure adapters.
library;

import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/hooks/hook_installer.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/pipeline.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/application/ports/working_tree.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_check.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:stagelatch/src/infrastructure/git/git_cli_repository.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:stagelatch/src/infrastructure/io/file_hook_store.dart';
import 'package:stagelatch/src/infrastructure/io/local_working_tree.dart';
import 'package:stagelatch/src/infrastructure/io/system_clock.dart';
import 'package:stagelatch/src/version.dart';

/// The wired tool: pipeline, hooks and the git processes behind them.
///
/// [create] is the production wiring. Tests build a [Composition] from
/// fakes through the constructor, so a check can be made to throw without
/// a real repository.
final class Composition {
  /// Wires already-built ports. Production code uses [create].
  new({
    required this.pipeline,
    required this.hookInstaller,
    required this.git,
    required this.documents,
    required this.registry,
    required this.loader,
    required this.worktree,
    required this.trackedHooks,
  });

  /// Builds the real adapters for [io] and reads the repository layout.
  ///
  /// Throws when [io] is not inside a git work tree.
  /// The git processes are closed by [close], including when layout fails.
  static Future<Composition> create(Io io) async {
    final process = GitProcess(
      workingDirectory: io.environment.workingDirectory,
      environment: io.environment.variables,
    );
    final git = GitCliRepository(git: process);
    try {
      final layout = await git.layout();
      const documents = StructuredDocuments();
      final worktree = LocalWorkingTree(layout.root);
      final registry = CheckRegistry(const [PubspecCheck()]);
      final loader = ConfigLoader(documents, worktree);
      final store = FileHookStore(
        hooksDirectory: layout.hooksDir,
        git: process,
      );
      return Composition(
        pipeline: Pipeline(
          git: git,
          configLoader: loader,
          registry: registry,
          documents: documents,
          clock: SystemClock(),
          toolVersion: Version.parse(packageVersion),
        ),
        hookInstaller: HookInstaller(store),
        git: git,
        documents: documents,
        registry: registry,
        loader: loader,
        worktree: worktree,
        trackedHooks: () => store.directoryIsTracked,
      );
    } on Exception {
      await git.close();
      rethrow;
    }
  }

  /// The pipeline `run` executes.
  final Pipeline pipeline;

  /// The installer `init`, `install` and `uninstall` use.
  final HookInstaller hookInstaller;

  /// The repository. [close] ends its processes.
  final GitRepository git;

  /// The YAML and JSON parser.
  final Documents documents;

  /// The checks of this version.
  final CheckRegistry registry;

  /// Loads `stagelatch.yaml` from the snapshot, then the working tree.
  final ConfigLoader loader;

  /// The working tree, rooted at the repository root.
  final WorkingTree worktree;

  /// Whether the hooks directory is tracked by git.
  final Future<bool> Function() trackedHooks;

  /// Ends the persistent git processes.
  Future<void> close() => git.close();
}

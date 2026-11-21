/// The only place that constructs infrastructure adapters.
library;

import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/hooks/hook_installer.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/pipeline/pipeline.dart';
import 'package:stagelatch/src/application/ports/doctor_probes.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/application/ports/hook_store.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/application/ports/working_tree.dart';
import 'package:stagelatch/src/application/why/why.dart';
import 'package:stagelatch/src/checks/analyze/analyze_check.dart';
import 'package:stagelatch/src/checks/assets/assets_check.dart';
import 'package:stagelatch/src/checks/codegen/codegen_check.dart';
import 'package:stagelatch/src/checks/format/format_check.dart';
import 'package:stagelatch/src/checks/l10n/l10n_check.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_check.dart';
import 'package:stagelatch/src/checks/sensitive_files/sensitive_files_check.dart';
import 'package:stagelatch/src/checks/tests/tests_check.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/infrastructure/dart/file_sdk_locator.dart';
import 'package:stagelatch/src/infrastructure/dart/process_test_runner.dart';
import 'package:stagelatch/src/infrastructure/dart/sdk_dart_toolchain.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:stagelatch/src/infrastructure/git/git_cli_repository.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:stagelatch/src/infrastructure/io/file_cache.dart';
import 'package:stagelatch/src/infrastructure/io/file_hook_store.dart';
import 'package:stagelatch/src/infrastructure/io/local_doctor_probes.dart';
import 'package:stagelatch/src/infrastructure/io/local_working_tree.dart';
import 'package:stagelatch/src/infrastructure/io/system_clock.dart';
import 'package:stagelatch/src/version.dart';

/// The checks of the tool, in the order of the documented hook lists.
///
/// The rule reference `docs/rules.md` is generated from this list.
const List<Check> productionChecks = [
  FormatCheck(),
  AnalyzeCheck(),
  PubspecCheck(),
  SensitiveFilesCheck(),
  AssetsCheck(),
  L10nCheck(),
  CodegenCheck(),
  TestsCheck(),
];

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
    this.hookStore,
    this.sdkLocator,
    this.doctorProbes,
    this.why,
  });

  /// Builds the real adapters for [io] and reads the repository layout.
  ///
  /// Throws when [io] is not inside a git work tree.
  /// The git processes are closed by [close], including when layout fails.
  ///
  /// [checks] replaces the production registry, in tests that need a
  /// different order (the determinism test of testing.md section 5).
  static Future<Composition> create(Io io, {List<Check>? checks}) async {
    final process = GitProcess(
      workingDirectory: io.environment.workingDirectory,
      environment: io.environment.variables,
    );
    final git = GitCliRepository(git: process);
    try {
      final layout = await git.layout();
      const documents = StructuredDocuments();
      final worktree = LocalWorkingTree(layout.root);
      // Registry order is the order of the documented hook lists.
      final registry = CheckRegistry(checks ?? productionChecks);
      final sdkLocator = FileSdkLocator(
        repoRoot: layout.root,
        environment: io.environment,
      );
      final loader = ConfigLoader(documents, worktree);
      final store = FileHookStore(
        hooksDirectory: layout.hooksDir,
        git: process,
      );
      final toolVersion = Version.parse(packageVersion);
      final toolchains = SdkDartToolchainFactory(
        cache: FileCache(commonDir: layout.commonDir),
      );
      return Composition(
        pipeline: Pipeline(
          git: git,
          configLoader: loader,
          registry: registry,
          documents: documents,
          clock: SystemClock(),
          toolVersion: toolVersion,
          sdkLocator: sdkLocator,
          toolchains: toolchains,
          testRunners: const ProcessTestRunnerFactory(),
        ),
        hookInstaller: HookInstaller(store),
        git: git,
        documents: documents,
        registry: registry,
        loader: loader,
        worktree: worktree,
        trackedHooks: () => store.directoryIsTracked,
        hookStore: store,
        sdkLocator: sdkLocator,
        doctorProbes: LocalDoctorProbes(
          repoRoot: layout.root,
          environment: io.environment,
        ),
        why: Why(
          git: git,
          configLoader: loader,
          registry: registry,
          documents: documents,
          sdkLocator: sdkLocator,
          toolchains: toolchains,
          toolVersion: toolVersion,
        ),
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

  /// The hook scripts, for `doctor`. Null in tests that need no doctor.
  final HookStore? hookStore;

  /// Finds the project's SDK. Null in tests that need no doctor.
  final SdkLocator? sdkLocator;

  /// The machine-facing questions of `doctor`. Null in tests that need no
  /// doctor.
  final DoctorProbes? doctorProbes;

  /// Explains affected-test selection. Null in tests that need no `why`.
  final Why? why;

  /// Ends the persistent git processes.
  Future<void> close() => git.close();
}

/// `stagelatch init`.
library;

import 'package:args/command_runner.dart' hide UsageException;
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/init/config_writer.dart';
import 'package:stagelatch/src/application/init/project_detector.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/install_flow.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/scope.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/version.dart';

/// Writes `stagelatch.yaml` and, unless `--no-hooks`, installs the hooks.
final class InitCommand extends Command<int> {
  /// Creates the command.
  new(this._io, this._open) {
    argParser
      ..addFlag('force', negatable: false, help: 'Overwrite stagelatch.yaml.')
      ..addFlag('no-hooks', negatable: false, help: 'Do not install hooks.');
  }

  final Io _io;
  final Future<Composition> Function(Io io) _open;

  @override
  String get name => 'init';

  @override
  String get description => 'Write stagelatch.yaml and install the hooks.';

  @override
  Future<int> run() async {
    final io = scopeCommand(this, _io);
    final force = argResults?.flag('force') ?? false;
    final noHooks = argResults?.flag('no-hooks') ?? false;
    final composition = await _open(io);
    try {
      final files = composition.git.files(const IndexSnapshot());
      final project = await ProjectDetector(
        files,
        composition.documents,
      ).detect();
      final path = RepoPath('stagelatch.yaml');
      if (!force && await composition.worktree.exists(path)) {
        throw const UsageException(
          'stagelatch.yaml already exists. Use --force to overwrite.',
        );
      }
      await composition.worktree.writeText(
        path,
        renderConfig(
          project,
          composition.registry,
          toolVersion: packageVersion,
        ),
      );
      io.stdout.writeln('Created stagelatch.yaml.');
      if (noHooks) return 0;
      return await installConfigured(composition, io, force: false);
    } finally {
      await composition.close();
    }
  }
}

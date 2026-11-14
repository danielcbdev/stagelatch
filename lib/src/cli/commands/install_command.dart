/// `stagelatch install` and `stagelatch uninstall`.
library;

import 'package:args/command_runner.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/hook_output.dart';
import 'package:stagelatch/src/cli/install_flow.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/scope.dart';

/// Installs the hook scripts named by the configuration.
final class InstallCommand extends Command<int> {
  /// Creates the command.
  new(this._io, this._open) {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Replace a hook this tool does not manage.',
    );
  }

  final Io _io;
  final Future<Composition> Function(Io io) _open;

  @override
  String get name => 'install';

  @override
  String get description => 'Install the hook scripts.';

  @override
  Future<int> run() async {
    final io = scopeCommand(this, _io);
    final composition = await _open(io);
    try {
      return await installConfigured(
        composition,
        io,
        force: argResults?.flag('force') ?? false,
      );
    } finally {
      await composition.close();
    }
  }
}

/// Removes managed hooks and restores the newest backup.
final class UninstallCommand extends Command<int> {
  /// Creates the command.
  new(this._io, this._open);

  final Io _io;
  final Future<Composition> Function(Io io) _open;

  @override
  String get name => 'uninstall';

  @override
  String get description => 'Remove the hook scripts this tool installed.';

  @override
  Future<int> run() async {
    final io = scopeCommand(this, _io);
    final composition = await _open(io);
    try {
      reportUninstall(io, await composition.hookInstaller.uninstall());
      return 0;
    } finally {
      await composition.close();
    }
  }
}

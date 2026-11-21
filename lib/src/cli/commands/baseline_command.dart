/// `stagelatch baseline create|prune` (docs/specs/cli.md).
library;

import 'package:args/command_runner.dart' hide UsageException;
import 'package:stagelatch/src/application/baseline/baseline_commands.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/scope.dart';

/// Adopts stagelatch in a legacy codebase: records today's findings so that
/// only new ones block (docs/specs/baseline-and-suppression.md section 4).
final class BaselineCommand extends Command<int> {
  /// Creates the command and its two subcommands.
  new(Io io, Future<Composition> Function(Io io) open) {
    addSubcommand(_BaselineCreate(io, open));
    addSubcommand(_BaselinePrune(io, open));
  }

  @override
  String get name => 'baseline';

  @override
  String get description =>
      'Record or trim the findings a legacy codebase is allowed to keep.';
}

/// Shared by the two subcommands: open the repository, run one of the
/// [BaselineCommands] and print what it returns.
abstract base class _BaselineSubcommand extends Command<int> {
  new(this.io, this.open);

  /// The streams and environment of the invocation.
  final Io io;

  /// Opens the repository the command works on.
  final Future<Composition> Function(Io io) open;

  Future<String> perform(BaselineCommands commands);

  @override
  Future<int> run() async {
    final scoped = scopeCommand(this, io);
    final composition = await open(scoped);
    try {
      final message = await perform(
        BaselineCommands(composition.pipeline, composition.worktree),
      );
      scoped.stdout.writeln(message);
      return 0;
    } finally {
      await composition.close();
    }
  }
}

final class _BaselineCreate extends _BaselineSubcommand {
  new(super.io, super.open) {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Overwrite an existing baseline file.',
    );
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Write every current finding to the baseline file.';

  @override
  Future<String> perform(BaselineCommands commands) =>
      commands.create(force: argResults?.flag('force') ?? false);
}

final class _BaselinePrune extends _BaselineSubcommand {
  new(super.io, super.open);

  @override
  String get name => 'prune';

  @override
  String get description =>
      'Drop baseline entries that no longer match a finding.';

  @override
  Future<String> perform(BaselineCommands commands) => commands.prune();
}

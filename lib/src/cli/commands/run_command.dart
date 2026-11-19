/// `stagelatch run`.
library;

import 'package:args/command_runner.dart' hide UsageException;
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/scope.dart';
import 'package:stagelatch/src/infrastructure/reporters/console_reporter.dart';

/// Runs the checks for one git hook.
final class RunCommand extends Command<int> {
  /// Creates the command.
  new(this._io, this._open) {
    argParser
      ..addFlag('all', negatable: false, help: 'Check every file.')
      ..addFlag('no-fix', negatable: false, help: 'Do not apply fixes.')
      ..addOption('reporter', help: 'console, the only reporter so far.');
  }

  final Io _io;
  final Future<Composition> Function(Io io) _open;

  @override
  String get name => 'run';

  @override
  String get description => 'Run the checks for a git hook.';

  @override
  Future<int> run() async {
    final io = scopeCommand(this, _io);
    final hook = argResults?.rest ?? const <String>[];
    final known =
        hook.length == 1 &&
        (hook.single == 'pre-commit' || hook.single == 'pre-push');
    if (!known) {
      final name = hook.isEmpty ? '' : hook.join(' ');
      throw UsageException(
        'Unknown hook "$name". Expected pre-commit or pre-push.',
      );
    }
    final reporter = argResults?.option('reporter');
    if (reporter != null && reporter != 'console') {
      throw UsageException('Unknown reporter "$reporter". Expected console.');
    }
    if (hook.single == 'pre-push') {
      throw const UsageException('pre-push arrives in 0.1.0.');
    }
    if (argResults?.flag('all') ?? false) {
      throw const UsageException('--all arrives in 0.2.0.');
    }
    final composition = await _open(io);
    try {
      final reports = await composition.pipeline.run(
        RunRequest(
          entry: const PreCommitEntry(),
          allowFixes: !(argResults?.flag('no-fix') ?? false),
        ),
      );
      ConsoleReporter(
        io.stdout,
        color: io.environment.useColor,
      ).report(reports);
      final failed = reports.any((report) => report.verdict == Verdict.fail);
      return failed ? 1 : 0;
    } finally {
      await composition.close();
    }
  }
}

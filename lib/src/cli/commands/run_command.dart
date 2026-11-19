/// `stagelatch run`.
library;

import 'dart:convert';

import 'package:args/command_runner.dart' hide UsageException;
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/hooks/pushed_refs.dart';
import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/reporter.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/scope.dart';
import 'package:stagelatch/src/infrastructure/reporters/console_reporter.dart';
import 'package:stagelatch/src/infrastructure/reporters/json_reporter.dart';
import 'package:stagelatch/src/version.dart';

/// Runs the checks for one git hook.
final class RunCommand extends Command<int> {
  /// Creates the command.
  new(this._io, this._open) {
    argParser
      ..addFlag('all', negatable: false, help: 'Check every file.')
      ..addFlag('no-fix', negatable: false, help: 'Do not apply fixes.')
      ..addOption('reporter', help: 'console (default) or json.');
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
    // Git calls pre-push with `<remote> <url>`, and the hook script passes
    // them on (docs/specs/cli.md, section 3.4). pre-commit takes none.
    final known = switch (hook) {
      ['pre-commit'] || ['pre-push'] || ['pre-push', _, _] => true,
      _ => false,
    };
    if (!known) {
      final name = hook.isEmpty ? '' : hook.join(' ');
      throw UsageException(
        'Unknown hook "$name". Expected pre-commit or pre-push.',
      );
    }
    final reporter = argResults?.option('reporter');
    if (reporter != null && reporter != 'console' && reporter != 'json') {
      throw UsageException(
        'Unknown reporter "$reporter". Expected console or json.',
      );
    }
    if (argResults?.flag('all') ?? false) {
      throw const UsageException('--all arrives in 0.2.0.');
    }
    final composition = await _open(io);
    try {
      final entry = hook.first == 'pre-push'
          ? await _prePush(
              io,
              composition,
              remote: hook.length == 3 ? hook[1] : null,
            )
          : const PreCommitEntry() as EntryPoint;
      final reports = await composition.pipeline.run(
        RunRequest(
          entry: entry,
          allowFixes: !(argResults?.flag('no-fix') ?? false),
        ),
      );
      (reporter == 'json'
              ? JsonReporter(io.stdout, toolVersion: packageVersion)
              : ConsoleReporter(io.stdout, color: io.environment.useColor)
                    as Reporter)
          .report(reports);
      final failed = reports.any((report) => report.verdict == Verdict.fail);
      return failed ? 1 : 0;
    } finally {
      await composition.close();
    }
  }

  /// The push to judge: the refs git wrote on standard input, or, for a
  /// manual run with nothing on it, the current branch towards its
  /// upstream. Standard input is read only when it is not a terminal, so
  /// a manual run never waits for input (ADR-0011).
  Future<PrePushEntry> _prePush(
    Io io,
    Composition composition, {
    required String? remote,
  }) async {
    final input = io.environment.stdinIsTerminal
        ? ''
        : await utf8.decodeStream(io.stdin);
    final refs = parsePushedRefs(input);
    if (refs.isEmpty) {
      return await composition.git.synthesizePrePush(remote: remote);
    }
    return PrePushEntry(remote: remote ?? 'origin', refs: refs);
  }
}

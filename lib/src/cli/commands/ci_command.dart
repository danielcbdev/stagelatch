/// `stagelatch ci` (docs/specs/cli.md, section 3.5).
library;

import 'package:args/command_runner.dart' hide UsageException;
import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/run_report.dart';
import 'package:stagelatch/src/application/ports/reporter.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/scope.dart';
import 'package:stagelatch/src/infrastructure/reporters/console_reporter.dart';
import 'package:stagelatch/src/infrastructure/reporters/github_reporter.dart';
import 'package:stagelatch/src/infrastructure/reporters/json_reporter.dart';
import 'package:stagelatch/src/version.dart';

/// Runs the same pipeline as the hooks over a pull request: the head
/// against its merge base with `--base` (ADR-0005, ADR-0007).
final class CiCommand extends Command<int> {
  /// Creates the command.
  new(this._io, this._open) {
    argParser
      ..addOption('base', help: 'The ref the change is to be merged into.')
      ..addOption('head', defaultsTo: 'HEAD', help: 'The ref to judge.')
      ..addFlag('all', negatable: false, help: 'Check every file.')
      ..addOption('reporter', help: 'console (default), json or github.');
  }

  final Io _io;
  final Future<Composition> Function(Io io) _open;

  @override
  String get name => 'ci';

  @override
  String get description => 'Run the checks over a pull request.';

  @override
  Future<int> run() async {
    final io = scopeCommand(this, _io);
    final base = argResults?.option('base');
    if (base == null || base.isEmpty) {
      throw const UsageException('ci needs --base <ref>.');
    }
    final head = argResults?.option('head') ?? 'HEAD';
    final reporter = argResults?.option('reporter') ?? 'console';
    if (!const {'console', 'json', 'github'}.contains(reporter)) {
      throw UsageException(
        'Unknown reporter "$reporter". Expected console, json or github.',
      );
    }
    if (argResults?.flag('all') ?? false) {
      throw const UsageException('--all arrives in 0.2.0.');
    }
    final composition = await _open(io);
    try {
      final reports = await composition.pipeline.run(
        RunRequest(
          entry: CiEntry(baseRef: base, headRef: head),
          // CI judges a commit and never writes to the index.
          allowFixes: false,
        ),
      );
      _reporter(reporter, io).report(reports);
      final failed = reports.any((report) => report.verdict == Verdict.fail);
      return failed ? 1 : 0;
    } finally {
      await composition.close();
    }
  }

  static Reporter _reporter(String name, Io io) => switch (name) {
    'json' => JsonReporter(io.stdout, toolVersion: packageVersion),
    'github' => GithubReporter(io.stdout),
    _ => ConsoleReporter(io.stdout, color: io.environment.useColor),
  };
}

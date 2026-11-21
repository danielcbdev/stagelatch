/// `stagelatch why <test-file>` (docs/specs/cli.md, section 3.8).
library;

import 'package:args/command_runner.dart' hide UsageException;
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/why/why.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/exit_codes.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/scope.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// Prints why `tests/affected` selects a test for the index against a base.
final class WhyCommand extends Command<int> {
  /// Creates the command.
  new(this._io, this._open) {
    argParser.addOption(
      'base',
      help:
          'Compare the index with this ref (default: upstream or origin/HEAD).',
    );
  }

  final Io _io;
  final Future<Composition> Function(Io io) _open;

  @override
  String get name => 'why';

  @override
  String get description => 'Explain why a test is selected by tests/affected.';

  @override
  String get invocation => 'stagelatch why <test-file> [--base <ref>]';

  @override
  Future<int> run() async {
    final io = scopeCommand(this, _io);
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw const UsageException('why expects exactly one test file path.');
    }
    final RepoPath testFile;
    try {
      testFile = RepoPath(rest.single);
    } on FormatException {
      throw UsageException('${rest.single} is not a test file of any package.');
    }
    final composition = await _open(io);
    try {
      final why = composition.why;
      if (why == null) {
        throw const InternalException(
          'why needs a Why use case.',
          where: 'why',
        );
      }
      final result = await why.explain(
        testFile,
        baseRef: argResults!.option('base'),
      );
      io.stdout.write(renderWhy(result));
      return ExitCode.pass.code;
    } finally {
      await composition.close();
    }
  }
}

/// `stagelatch doctor` (docs/specs/cli.md, section 3.6).
library;

import 'dart:convert';

import 'package:args/command_runner.dart' hide UsageException;
import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/doctor/doctor.dart';
import 'package:stagelatch/src/application/doctor/probe_result.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/scope.dart';
import 'package:stagelatch/src/version.dart';

/// Diagnoses hooks, `core.hooksPath`, the resolved SDK, `PATH` and
/// `min_version`.
final class DoctorCommand extends Command<int> {
  /// Creates the command.
  new(this._io, this._open) {
    argParser.addOption('reporter', help: 'console (default) or json.');
  }

  final Io _io;
  final Future<Composition> Function(Io io) _open;

  @override
  String get name => 'doctor';

  @override
  String get description => 'Check that the hooks and the gate can work.';

  @override
  Future<int> run() async {
    final io = scopeCommand(this, _io);
    final reporter = argResults?.option('reporter') ?? 'console';
    if (reporter != 'console' && reporter != 'json') {
      throw UsageException(
        'Unknown reporter "$reporter". Expected console or json.',
      );
    }
    final composition = await _open(io);
    try {
      final hooks = composition.hookStore;
      final sdk = composition.sdkLocator;
      final probes = composition.doctorProbes;
      if (hooks == null || sdk == null || probes == null) {
        throw const InternalException(
          'doctor needs a hook store, an SDK locator and probes.',
          where: 'doctor',
        );
      }
      final results = await Doctor(
        git: composition.git,
        hooks: hooks,
        loader: composition.loader,
        documents: composition.documents,
        worktree: composition.worktree,
        catalog: composition.registry,
        sdk: sdk,
        environment: io.environment,
        probes: probes,
        toolVersion: Version.parse(packageVersion),
      ).run();
      final code = doctorExitCode(results);
      if (reporter == 'json') {
        io.stdout.writeln(
          const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': 1,
            'probes': [
              for (final result in results)
                {
                  'id': result.id,
                  'status': result.status.name,
                  'message': result.message,
                },
            ],
            'exitCode': code,
          }),
        );
      } else {
        for (final result in results) {
          io.stdout.writeln(result.toConsoleLine());
        }
      }
      return code;
    } finally {
      await composition.close();
    }
  }
}

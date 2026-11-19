/// Shared steps of `init` and `install`.
library;

import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/hooks/hook_name.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/hook_output.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/version.dart';

/// Installs every git hook named in the loaded configuration.
Future<int> installConfigured(
  Composition composition,
  Io io, {
  required bool force,
}) async {
  final loaded = await composition.loader.load(
    composition.git.files(const IndexSnapshot()),
    toolVersion: Version.parse(packageVersion),
    catalog: composition.registry,
  );
  for (final notice in loaded.notices) {
    io.stdout.writeln('note: $notice');
  }
  final hooks = {
    for (final hook in HookName.values)
      if (loaded.config.hooks.containsKey(hook.fileName)) hook,
  };
  final actions = await composition.hookInstaller.install(hooks, force: force);
  final code = reportInstall(io, actions);
  if (code == 0 && await composition.trackedHooks()) {
    io.stdout.writeln(
      'The hooks directory is tracked by git; the generated script will '
      'show up as a change.',
    );
  }
  return code;
}

import 'dart:convert';

import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/checks/analyze/analyze_check.dart';
import 'package:stagelatch/src/checks/assets/assets_check.dart';
import 'package:stagelatch/src/checks/codegen/codegen_check.dart';
import 'package:stagelatch/src/checks/format/format_check.dart';
import 'package:stagelatch/src/checks/l10n/l10n_check.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_check.dart';
import 'package:stagelatch/src/checks/sensitive_files/sensitive_files_check.dart';
import 'package:stagelatch/src/cli/composition.dart';
import 'package:stagelatch/src/cli/io.dart';
import 'package:stagelatch/src/cli/runner.dart';
import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

/// [json] with every `durationMs` field removed, re-encoded.
String withoutDurations(String json) {
  Object? strip(Object? value) => switch (value) {
    final Map<String, Object?> map => {
      for (final entry in map.entries)
        if (entry.key != 'durationMs') entry.key: strip(entry.value),
    },
    final List<Object?> list => [for (final item in list) strip(item)],
    _ => value,
  };
  return jsonEncode(strip(jsonDecode(json)));
}

void main() {
  // docs/engineering/testing.md, section 5.
  test('two runs with --reporter json are byte-identical once durationMs is '
      'removed', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.stageContent('pubspec.yaml', badPubspec);
    const args = ['run', 'pre-commit', '--reporter', 'json'];

    final first = await repo.stagelatch(args);
    final second = await repo.stagelatch(args);

    expect(first.exitCode, 1);
    expect(withoutDurations(first.stdout), withoutDurations(second.stdout));
    expect(
      (jsonDecode(first.stdout) as Map<String, Object?>)['verdict'],
      'fail',
    );
  });

  test('a reversed check registry gives the same JSON once durationMs is '
      'removed and the per-check rows are put in id order', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await addDartPackage(repo);
    await repo.stageContent(
      'pubspec.yaml',
      'name: app\nenvironment:\n  sdk: ^3.0.0\n'
          'dependencies:\n  design_system:\n    path: ../x\n',
    );
    await repo.stageContent('.env', 'TOKEN=1\n');
    await repo.stageContent('lib/a.dart', 'void main( ) {\n}\n');
    const args = ['run', 'pre-commit', '--no-fix', '--reporter', 'json'];

    final forward = await repo.stagelatch(args);
    final out = StringBuffer();
    final code = await runStagelatch(
      args,
      Io(
        stdout: out,
        stderr: StringBuffer(),
        stdin: const Stream.empty(),
        environment: Environment(
          workingDirectory: repo.root,
          variables: repo.environment,
          stdoutIsTerminal: false,
          stdinIsTerminal: false,
        ),
      ),
      open: (io) => Composition.create(
        io,
        checks: const [
          CodegenCheck(),
          L10nCheck(),
          AssetsCheck(),
          SensitiveFilesCheck(),
          PubspecCheck(),
          AnalyzeCheck(),
          FormatCheck(),
        ],
      ),
    );

    expect(forward.exitCode, 1);
    expect(code, forward.exitCode);
    expect(_normalized(out.toString()), _normalized(forward.stdout));
    expect(
      (jsonDecode(forward.stdout) as Map<String, Object?>)['findings'],
      hasLength(3),
    );
  });
}

/// [json] without durations, with the `checks` rows sorted by id: the
/// table follows registry order by design (cli.md section 4), everything
/// else must not depend on it.
String _normalized(String json) {
  final decoded = jsonDecode(withoutDurations(json)) as Map<String, Object?>;
  final checks = [...(decoded['checks']! as List<Object?>)]
    ..sort(
      (a, b) => ((a! as Map)['id']! as String).compareTo(
        (b! as Map)['id']! as String,
      ),
    );
  return jsonEncode({...decoded, 'checks': checks});
}

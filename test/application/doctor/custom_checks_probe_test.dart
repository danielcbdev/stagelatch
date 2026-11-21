import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/doctor/doctor.dart';
import 'package:stagelatch/src/application/doctor/probe_result.dart';
import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/ports/doctor_probes.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_git_repository.dart';
import '../../support/fake_hook_store.dart';
import '../../support/fake_sdk_locator.dart';
import '../../support/fake_working_tree.dart';

final class _Probes implements DoctorProbes {
  new({this.onPath = const {}});

  final Map<String, String> onPath;

  @override
  Future<String?> gitVersion() async => 'git version 2.56.0';

  @override
  Future<String?> resolveOnPath(String name) async => onPath[name];

  @override
  Future<bool> globallyActivated() async => false;

  @override
  Future<bool> packageConfigExists(RepoPath? packageRoot) async => true;
}

Future<List<ProbeResult>> _run({
  required Map<String, Object> index,
  Map<String, String> onPath = const {},
  FakeSdkLocator? sdk,
}) {
  final tree = FakeWorkingTree();
  return Doctor(
    git: FakeGitRepository(index: index),
    hooks: FakeHookStore(),
    loader: ConfigLoader(const StructuredDocuments(), tree),
    documents: const StructuredDocuments(),
    worktree: tree,
    catalog: CheckRegistry(const []),
    sdk: sdk ?? FakeSdkLocator(),
    environment: Environment(
      workingDirectory: '/repo',
      variables: const {'SECRET_TOKEN': 'do-not-print'},
      stdoutIsTerminal: false,
      stdinIsTerminal: false,
    ),
    probes: _Probes(onPath: onPath),
    toolVersion: Version.parse('0.3.0'),
  ).run();
}

void main() {
  test('doctor lists each custom check id and the resolved command', () async {
    final results = await _run(
      index: {
        'stagelatch.yaml': '''
custom_checks:
  team:
    run: [python, tool/check.py]
    sources: [tool/check.py]
  other:
    run: [dart, run, tool/other.dart]
''',
        'tool/check.py': 'print(1)\n',
        'tool/other.dart': 'void main() {}\n',
      },
      onPath: {'python': '/usr/bin/python3'},
      sdk: FakeSdkLocator(
        sdk: const ResolvedSdk(
          root: '/sdk',
          dartExecutable: '/sdk/bin/dart',
          flutterExecutable: '/sdk/bin/flutter',
          version: '3.13.0',
          source: SdkSource.path,
        ),
      ),
    );

    final custom = results.where((r) => r.id == 'D10').toList();
    expect(custom, hasLength(2));

    final team = custom.firstWhere((r) => r.message.contains('"team"'));
    expect(team.status, ProbeStatus.ok);
    expect(team.message, contains('/usr/bin/python3'));
    expect(team.message, contains('tool/check.py'));
    expect(team.message, isNot(contains('SECRET_TOKEN')));
    expect(team.message, isNot(contains('do-not-print')));

    final other = custom.firstWhere((r) => r.message.contains('"other"'));
    expect(other.status, ProbeStatus.ok);
    expect(other.message, contains('/sdk/bin/dart'));
    expect(other.message, contains('run tool/other.dart'));
  });

  test('doctor warns when the custom-check executable is missing', () async {
    final results = await _run(
      index: {
        'stagelatch.yaml': '''
custom_checks:
  team:
    run: [missing-bin, tool/check.py]
    sources: [tool/check.py]
''',
        'tool/check.py': 'print(1)\n',
      },
    );

    final team = results.singleWhere((r) => r.id == 'D10');
    expect(team.status, ProbeStatus.warn);
    expect(team.message, contains('"team"'));
    expect(team.message, contains('executable not found'));
  });

  test('doctor emits no D10 when custom_checks is empty', () async {
    final results = await _run(
      index: {'stagelatch.yaml': 'hooks:\n  pre-commit: [pubspec]\n'},
    );

    expect(results.where((r) => r.id == 'D10'), isEmpty);
  });
}

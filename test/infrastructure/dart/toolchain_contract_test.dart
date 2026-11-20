/// The contract of the Dart toolchain (ADR-0008, specs/dart-toolchain.md
/// sections 4, 5 and 7). These tests are the parity proof: they never
/// mention how the answers are produced, and they may not be weakened.
@Tags(['git'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/file_sdk_locator.dart';
import 'package:stagelatch/src/infrastructure/dart/sdk_dart_toolchain.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_snapshot_files.dart';
import '../../support/fake_working_tree.dart';
import '../../support/fixture_package.dart';
import '../../support/oracle.dart';

const _broken = '''
import 'dart:async';

void main() {
  print("hello");
  undefinedName();
}
''';

const _clean = 'void main() {}\n';

const _options =
    'formatter:\n  page_width: 100\n\n'
    'linter:\n  rules:\n    - avoid_print\n    - prefer_single_quotes\n';

void main() {
  late ResolvedSdk sdk;
  late String root;

  setUpAll(() async {
    final config =
        (await ConfigLoader(
              const StructuredDocuments(),
              FakeWorkingTree(),
            ).load(
              FakeSnapshotFiles({'stagelatch.yaml': 'hooks: {}\n'}),
              toolVersion: Version.parse('0.1.0'),
              catalog: CheckRegistry(const []),
            ))
            .config;
    sdk = await FileSdkLocator(
      repoRoot: Directory.systemTemp.path,
      environment: Environment(
        workingDirectory: Directory.current.path,
        variables: Platform.environment,
        stdoutIsTerminal: false,
        stdinIsTerminal: false,
      ),
    ).locate(config);
  });

  setUp(() async {
    root = await copyFixturePackage();
  });

  tearDown(() => Directory(root).delete(recursive: true));

  /// The files of the package on disk, minus `.dart_tool`, as a snapshot,
  /// with [overrides] applied: a null value removes the path.
  Future<FakeSnapshotFiles> snapshot([
    Map<String, String?> overrides = const {},
  ]) async {
    final files = <String, Object>{};
    await for (final entity in Directory(root).list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: root)
          .replaceAll(r'\', '/');
      if (relative.startsWith('.dart_tool/') || relative == 'pubspec.lock') {
        continue;
      }
      files[relative] = await entity.readAsString();
    }
    for (final MapEntry(:key, :value) in overrides.entries) {
      if (value == null) {
        files.remove(key);
      } else {
        files[key] = value;
      }
    }
    return FakeSnapshotFiles(files);
  }

  DartToolchain toolchain(FakeSnapshotFiles files) {
    final created = const SdkDartToolchainFactory().create(
      sdk: sdk,
      repoRoot: root,
      snapshot: files,
      packages: PackageMap(const [DartPackage(root: null, name: 'dart_app')]),
    );
    addTearDown(created.close);
    return created;
  }

  int stagelatchTempDirectories() => Directory.systemTemp
      .listSync()
      .where((entry) => p.basename(entry.path).startsWith('stagelatch-'))
      .length;

  test(
    'diagnostics equal dart analyze on a tree identical to the snapshot',
    () async {
      await writeFile(root, 'lib/a.dart', _broken);
      await writeFile(
        root,
        'lib/b.dart',
        "// TODO(someone): later.\nint b = 'not an int';\n",
      );
      final oracle = await runOracle(root);
      final dart = toolchain(await snapshot());

      final diagnostics = await dart.diagnose({
        RepoPath('lib/a.dart'),
        RepoPath('lib/b.dart'),
      });

      expect(oracle.diagnostics, isNotEmpty);
      expect(diagnostics, equalsOracle(oracle));
    },
  );

  test('a TODO is reported only when analysis_options raises it, as dart '
      'analyze does', () async {
    await writeFile(root, 'lib/a.dart', '// TODO(x): y.\nint a = 1;\n');
    await writeFile(
      root,
      'analysis_options.yaml',
      'analyzer:\n  errors:\n    todo: warning\n$_options',
    );
    final oracle = await runOracle(root);
    final dart = toolchain(await snapshot());

    final diagnostics = await dart.diagnose({RepoPath('lib/a.dart')});

    expect(diagnostics.map((d) => d.code), ['todo']);
    expect(diagnostics, equalsOracle(oracle));
  });

  test('the snapshot content wins over the file on disk', () async {
    await writeFile(root, 'lib/a.dart', _broken);
    final dart = toolchain(await snapshot({'lib/a.dart': _clean}));

    expect(await dart.diagnose({RepoPath('lib/a.dart')}), isEmpty);
  });

  test('an unstaged error in an imported file does not leak', () async {
    await writeFile(root, 'lib/dep.dart', 'int dep = "x";\n');
    await writeFile(
      root,
      'lib/uses_dep.dart',
      "import 'dep.dart';\n\nint uses = dep;\n",
    );
    final dart = toolchain(await snapshot({'lib/dep.dart': 'int dep = 1;\n'}));

    expect(await dart.diagnose({RepoPath('lib/uses_dep.dart')}), isEmpty);
  });

  test(
    'a file on disk that is absent from the snapshot is invisible',
    () async {
      await writeFile(root, 'lib/gone.dart', 'int gone = 1;\n');
      await writeFile(
        root,
        'lib/uses_gone.dart',
        "import 'gone.dart';\n\nint uses = gone;\n",
      );
      final dart = toolchain(await snapshot({'lib/gone.dart': null}));

      final diagnostics = await dart.diagnose({RepoPath('lib/uses_gone.dart')});

      expect(diagnostics.map((d) => d.code), contains('uri_does_not_exist'));
    },
  );

  test('only requested files are reported', () async {
    await writeFile(root, 'lib/a.dart', _broken);
    await writeFile(root, 'lib/b.dart', _broken);
    final dart = toolchain(await snapshot());

    final diagnostics = await dart.diagnose({RepoPath('lib/b.dart')});

    expect(diagnostics, isNotEmpty);
    expect(diagnostics.map((d) => d.location.path.value).toSet(), {
      'lib/b.dart',
    });
  });

  test('ignore comments and analysis_options are honored', () async {
    await writeFile(
      root,
      'lib/a.dart',
      'void main() {\n'
          '  // ignore: avoid_print\n'
          "  print('x');\n"
          '}\n',
    );
    await writeFile(
      root,
      'analysis_options.yaml',
      'analyzer:\n  errors:\n    prefer_single_quotes: ignore\n$_options',
    );
    await writeFile(root, 'lib/b.dart', 'String b = "double";\n');
    final oracle = await runOracle(root);
    final dart = toolchain(await snapshot());

    final diagnostics = await dart.diagnose({
      RepoPath('lib/a.dart'),
      RepoPath('lib/b.dart'),
    });

    expect(diagnostics, isEmpty);
    expect(diagnostics, equalsOracle(oracle));
  });

  test('locations and messages name repository paths, never the temporary '
      'directory', () async {
    await writeFile(root, 'lib/a.dart', "import 'missing.dart';\n");
    final dart = toolchain(await snapshot());

    final diagnostics = await dart.diagnose({RepoPath('lib/a.dart')});

    expect(diagnostics.first.location.path, RepoPath('lib/a.dart'));
    expect(
      diagnostics.every((d) => !d.message.contains('stagelatch-')),
      isTrue,
    );
  });

  test('format equals dart format, including page_width from '
      'analysis_options', () async {
    const long =
        'void main() { final values = [1111111111, 2222222222, 3333333333, '
        '4444444444, 5555555555, 6666666666, 7777777777]; print(values); }\n';
    await writeFile(root, 'lib/a.dart', long);
    final oracle = await runOracle(root, format: ['lib/a.dart']);
    final dart = toolchain(await snapshot());

    final outcome = await dart.format(RepoPath('lib/a.dart'), long);

    expect((outcome as Formatted).text, oracle.formatted['lib/a.dart']);
    expect(outcome.text, isNot(long));
  });

  test(
    'an unstaged page_width change does not change the formatted text',
    () async {
      const source =
          'void main() { print([111111111, 222222222, 333333333, '
          '444444444]); }\n';
      final staged = await toolchain(await snapshot())
          .format(RepoPath('lib/a.dart'), source);
      await writeFile(
        root,
        'analysis_options.yaml',
        'formatter:\n  page_width: 40\n',
      );

      final unstaged = await toolchain(
        await snapshot({'analysis_options.yaml': _options}),
      ).format(RepoPath('lib/a.dart'), source);

      expect((unstaged as Formatted).text, (staged as Formatted).text);
    },
  );

  test('format keeps CRLF when the input uses CRLF', () async {
    final dart = toolchain(await snapshot());

    final outcome = await dart.format(
      RepoPath('lib/a.dart'),
      'void main( ) {\r\n}\r\n',
    );

    expect((outcome as Formatted).text, 'void main() {}\r\n');
  });

  test('format of unparseable source is Unparseable', () async {
    final dart = toolchain(await snapshot());

    expect(
      await dart.format(RepoPath('lib/a.dart'), 'void main( {\n'),
      isA<Unparseable>(),
    );
  });

  test(
    'facts come from the snapshot and are null for an absent file',
    () async {
      final files = await snapshot({'lib/a.dart': "import 'b.dart';\n"});
      final dart = toolchain(files);

      final facts = await dart.facts(files, RepoPath('lib/a.dart'));

      expect(facts!.directives.single.kind, DirectiveKind.import);
      expect(await dart.facts(files, RepoPath('lib/none.dart')), isNull);
    },
  );

  test(
    'a package without .dart_tool/package_config.json is a usage error',
    () async {
      await Directory(p.join(root, '.dart_tool')).delete(recursive: true);
      await writeFile(root, 'lib/a.dart', _clean);
      final dart = toolchain(await snapshot());

      await expectLater(
        dart.diagnose({RepoPath('lib/a.dart')}),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            'Missing .dart_tool/package_config.json. Run: dart pub get',
          ),
        ),
      );
    },
  );

  test('close ends every child process and removes every directory it '
      'wrote', () async {
    await writeFile(root, 'lib/a.dart', _clean);
    final before = stagelatchTempDirectories();
    final dart = toolchain(await snapshot());
    await dart.diagnose({RepoPath('lib/a.dart')});
    await dart.format(RepoPath('lib/a.dart'), _clean);

    await dart.close();

    expect(stagelatchTempDirectories(), before);
  });
}

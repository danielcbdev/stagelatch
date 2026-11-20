import 'package:stagelatch/src/checks/l10n/l10n_setup.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_snapshot_files.dart';

Future<L10nSetup?> _setup(
  Map<String, Object> files, {
  DartPackage package = const DartPackage(root: null, name: 'app'),
}) => readL10nSetup(
  FakeSnapshotFiles(files),
  const StructuredDocuments(),
  package,
);

void main() {
  test(
    'defaults are lib/l10n and app_en.arb; l10n.yaml overrides them',
    () async {
      final defaults = await _setup({'l10n.yaml': '# nothing set\n'});
      final empty = await _setup({'l10n.yaml': ''});
      final custom = await _setup({
        'l10n.yaml':
            'arb-dir: res/strings\ntemplate-arb-file: intl_en.arb\n'
            'output-dir: lib/gen\nnullable-getter: false\n',
      });

      expect(defaults!.arbDir, RepoPath('lib/l10n'));
      expect(defaults.templateFile, 'app_en.arb');
      expect(defaults.outputDir, isNull);
      expect(empty!.arbDir, RepoPath('lib/l10n'));
      expect(custom!.arbDir, RepoPath('res/strings'));
      expect(custom.templateFile, 'intl_en.arb');
      expect(custom.outputDir, RepoPath('lib/gen'));
    },
  );

  test('a package without l10n.yaml is skipped', () async {
    expect(await _setup({'pubspec.yaml': 'name: app\n'}), isNull);
    // An l10n.yaml of another package is not this package's.
    expect(
      await _setup({'packages/ui/l10n.yaml': ''}),
      isNull,
      reason: 'the root package has no l10n.yaml of its own',
    );
  });

  test('paths are relative to the package', () async {
    final setup = await _setup({
      'packages/ui/l10n.yaml': 'arb-dir: lib/l10n\noutput-dir: lib/gen\n',
    }, package: DartPackage(root: RepoPath('packages/ui'), name: 'ui'));

    expect(setup!.arbDir, RepoPath('packages/ui/lib/l10n'));
    expect(setup.outputDir, RepoPath('packages/ui/lib/gen'));
  });

  test('./ and a trailing slash are normalized', () async {
    final setup = await _setup({'l10n.yaml': 'arb-dir: ./lib/l10n/\n'});

    expect(setup!.arbDir, RepoPath('lib/l10n'));
  });

  test('a directory outside the package makes the setup unusable', () async {
    expect(await _setup({'l10n.yaml': 'arb-dir: ../other\n'}), isNull);
    expect(await _setup({'l10n.yaml': 'arb-dir: /abs/path\n'}), isNull);
    expect(await _setup({'l10n.yaml': 'output-dir: ../gen\n'}), isNull);
  });

  test(
    'an l10n.yaml that is not valid YAML, or not a map, is skipped',
    () async {
      expect(await _setup({'l10n.yaml': 'arb-dir: [a, b\n'}), isNull);
      expect(await _setup({'l10n.yaml': '- a\n- b\n'}), isNull);
    },
  );

  test('a value that is not a string falls back to the default', () async {
    final setup = await _setup({
      'l10n.yaml': 'arb-dir: 3\ntemplate-arb-file: [a]\n',
    });

    expect(setup!.arbDir, RepoPath('lib/l10n'));
    expect(setup.templateFile, 'app_en.arb');
  });
}

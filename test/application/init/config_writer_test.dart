import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/init/config_writer.dart';
import 'package:stagelatch/src/application/init/project_detector.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_check_catalog.dart';
import '../../support/fake_snapshot_files.dart';
import '../../support/fake_working_tree.dart';

const _schemaUrl =
    'https://raw.githubusercontent.com/danielcbdev/stagelatch/main/schema/stagelatch.schema.json';
const _schemaComment = '# yaml-language-server: \$schema=$_schemaUrl\n';

String _render({
  bool codegen = false,
  bool l10n = false,
  bool assets = false,
}) => renderConfig(
  DetectedProject(
    usesFlutter: true,
    usesFvm: false,
    usesCodegen: codegen,
    usesL10n: l10n,
    usesAssets: assets,
  ),
  FakeCheckCatalog.full(),
  toolVersion: '0.2.0',
);

/// The selectors listed under [hook] in [text].
List<String> _hook(String text, String hook) {
  final line = text
      .split('\n')
      .firstWhere((line) => line.startsWith('  $hook: ['));
  return line
      .substring(line.indexOf('[') + 1, line.length - 1)
      .split(', ')
      .where((selector) => selector.isNotEmpty)
      .toList();
}

void main() {
  test('the first line points editors at the published schema', () {
    expect(_render(), startsWith(_schemaComment));
  });

  test('a plain project gets the checks that need no detection', () {
    expect(_hook(_render(), 'pre-commit'), [
      'format',
      'pubspec',
      'sensitive-files',
      'tests/solo',
      'tests/new-skip',
    ]);
  });

  test('codegen is listed only when build_runner is a dev dependency', () {
    expect(_hook(_render(), 'pre-commit'), isNot(contains('codegen')));
    expect(
      _hook(_render(codegen: true), 'pre-commit'),
      containsAllInOrder(['format', 'codegen', 'pubspec']),
    );
  });

  test('l10n is listed only with an l10n.yaml, and assets only when the '
      'pubspec declares assets', () {
    final plain = _hook(_render(), 'pre-commit');
    expect(plain, isNot(contains('l10n')));
    expect(plain, isNot(contains('assets')));

    expect(_hook(_render(l10n: true), 'pre-commit'), contains('l10n'));
    expect(_hook(_render(l10n: true), 'pre-commit'), isNot(contains('assets')));
    expect(_hook(_render(assets: true), 'pre-commit'), contains('assets'));
    expect(_hook(_render(assets: true), 'pre-commit'), isNot(contains('l10n')));
  });

  test('tests/solo and tests/new-skip are always on pre-commit, and '
      'tests/affected never is', () {
    for (final text in [
      _render(),
      _render(codegen: true, l10n: true, assets: true),
    ]) {
      final preCommit = _hook(text, 'pre-commit');
      expect(preCommit, containsAll(['tests/solo', 'tests/new-skip']));
      expect(preCommit, isNot(contains('tests/affected')));
    }
  });

  test('the text uses LF, ends with one newline and states the version', () {
    final text = _render();

    expect(text, isNot(contains('\r')));
    expect(text, endsWith('\n'));
    expect(text, isNot(endsWith('\n\n')));
    expect(text, contains('\nmin_version: 0.2.0\n'));
  });

  test('what init writes is a configuration the loader accepts', () async {
    final text = _render(codegen: true, l10n: true, assets: true);

    final loaded =
        await ConfigLoader(const StructuredDocuments(), FakeWorkingTree()).load(
          FakeSnapshotFiles({'stagelatch.yaml': text}),
          toolVersion: Version.parse('0.2.0'),
          catalog: FakeCheckCatalog.full(),
        );

    expect(loaded.config.minVersion, Version.parse('0.2.0'));
    expect(loaded.config.hooks['pre-commit'], hasLength(8));
  });
}

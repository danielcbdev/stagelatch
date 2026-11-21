import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/config/settings.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_check_catalog.dart';
import '../../support/fake_snapshot_files.dart';
import '../../support/fake_working_tree.dart';
import '../../support/temp_repo.dart';
import 'fixtures_path.dart';

final _toolVersion = Version.parse('0.3.0');

Future<LoadedConfig> _load(String yaml) =>
    ConfigLoader(const StructuredDocuments(), FakeWorkingTree()).load(
      FakeSnapshotFiles({'stagelatch.yaml': yaml}),
      toolVersion: _toolVersion,
      catalog: FakeCheckCatalog.full(),
    );

void main() {
  test('empty config fixture yields documented defaults', () async {
    final config = (await _load(
      readCompatFixture('config/valid_defaults.yaml'),
    )).config;

    expect(config.minVersion, isNull);
    expect(config.timeBudget, const Duration(seconds: 2));
    expect(config.baselinePath, RepoPath('.stagelatch/baseline.json'));
    expect(config.settings<FormatSettings>().fix, isTrue);
    expect(config.settings<AnalyzeSettings>().scope, AnalyzeScope.affected);
    expect(config.settings<AnalyzeSettings>().failOn, {
      DiagnosticSeverity.error,
      DiagnosticSeverity.warning,
    });
    expect(config.settings<AssetsSettings>().maxFileSize, 512000);
    expect(config.customChecks, isEmpty);
  });

  test('full config fixture parses keys including custom_checks', () async {
    final config = (await _load(readCompatFixture('config/valid_full.yaml')))
        .config;

    expect(config.minVersion, Version.parse('0.3.0'));
    expect(config.rules[RuleId.parse('tests/new-skip')], RuleLevel.warning);
    expect(config.rules[RuleId.parse('pubspec/unpinned-git')], RuleLevel.off);
    expect(config.customChecks, hasLength(1));
    final custom = config.customChecks.single;
    expect(custom.id, 'team');
    expect(custom.run, ['dart', 'run', 'tool/team_check.dart']);
    expect(custom.timeout, const Duration(seconds: 60));
    expect(custom.rules['no-print'], RuleLevel.error);
  });

  test(
    'reject fixtures throw ConfigException without asserting message text',
    () async {
      for (final name in [
        'config/reject_unknown_key.yaml',
        'config/reject_wrong_type.yaml',
        'config/reject_shadow_builtin.yaml',
      ]) {
        expect(
          () => _load(readCompatFixture(name)),
          throwsA(isA<ConfigException>()),
          reason: name,
        );
      }
    },
  );

  test('invalid staged config exits 78 via the CLI', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.write(
      'stagelatch.yaml',
      readCompatFixture('config/reject_unknown_key.yaml'),
    );
    await repo.stage('stagelatch.yaml');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 78);
  }, tags: ['git']);
}

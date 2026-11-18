import 'package:stagelatch/src/application/init/project_detector.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_snapshot_files.dart';

/// What [ProjectDetector] reports for a snapshot made of [files].
Future<DetectedProject> _detect(Map<String, Object> files) => ProjectDetector(
  FakeSnapshotFiles(files),
  const StructuredDocuments(),
).detect();

/// The facts as a record, so one assertion compares all of them.
({bool flutter, bool fvm, bool codegen, bool l10n, bool assets}) _facts(
  DetectedProject project,
) => (
  flutter: project.usesFlutter,
  fvm: project.usesFvm,
  codegen: project.usesCodegen,
  l10n: project.usesL10n,
  assets: project.usesAssets,
);

const _nothing = (
  flutter: false,
  fvm: false,
  codegen: false,
  l10n: false,
  assets: false,
);

const _pureDart = '''
name: app
environment:
  sdk: ^3.13.0
dependencies:
  path: ^1.9.1
dev_dependencies:
  test: ^1.33.0
''';

void main() {
  group('ProjectDetector', () {
    test('detects nothing in a pure Dart package', () async {
      final project = await _detect({'pubspec.yaml': _pureDart});

      expect(_facts(project), _nothing);
    });

    test('detects nothing in a repository without a pubspec', () async {
      final project = await _detect({'README.md': '# app\n'});

      expect(_facts(project), _nothing);
    });

    test('detects Flutter from a flutter SDK dependency', () async {
      final project = await _detect({
        'pubspec.yaml': '''
name: app
dependencies:
  flutter:
    sdk: flutter
''',
      });

      expect(_facts(project), (
        flutter: true,
        fvm: false,
        codegen: false,
        l10n: false,
        assets: false,
      ));
    });

    test('detects Flutter from a flutter SDK dev dependency', () async {
      final project = await _detect({
        'pubspec.yaml': '''
name: app
dev_dependencies:
  flutter:
    sdk: flutter
''',
      });

      expect(project.usesFlutter, isTrue);
    });

    test('detects Flutter in a nested package', () async {
      final project = await _detect({
        'pubspec.yaml': _pureDart,
        'packages/ui/pubspec.yaml': '''
name: ui
dependencies:
  flutter:
    sdk: flutter
''',
      });

      expect(project.usesFlutter, isTrue);
    });

    test('ignores a hosted package that happens to be named flutter', () async {
      final project = await _detect({
        'pubspec.yaml': '''
name: app
dependencies:
  flutter: ^1.0.0
''',
      });

      expect(project.usesFlutter, isFalse);
    });

    test('detects FVM from a .fvmrc file', () async {
      final project = await _detect({
        'pubspec.yaml': _pureDart,
        '.fvmrc': '{"flutter": "3.38.0"}\n',
      });

      expect(_facts(project), (
        flutter: false,
        fvm: true,
        codegen: false,
        l10n: false,
        assets: false,
      ));
    });

    test('detects FVM from a .fvm directory', () async {
      final project = await _detect({
        'pubspec.yaml': _pureDart,
        '.fvm/fvm_config.json': '{"flutterSdkVersion": "3.38.0"}\n',
      });

      expect(project.usesFvm, isTrue);
    });

    test('detects code generation from build_runner in dev_dependencies', () async {
      final project = await _detect({
        'pubspec.yaml': '''
name: app
dev_dependencies:
  build_runner: ^2.4.0
''',
      });

      expect(_facts(project), (
        flutter: false,
        fvm: false,
        codegen: true,
        l10n: false,
        assets: false,
      ));
    });

    test('ignores build_runner outside dev_dependencies', () async {
      final project = await _detect({
        'pubspec.yaml': '''
name: app
dependencies:
  build_runner: ^2.4.0
''',
      });

      expect(project.usesCodegen, isFalse);
    });

    test('detects l10n from an l10n.yaml file', () async {
      final project = await _detect({
        'pubspec.yaml': _pureDart,
        'l10n.yaml': 'arb-dir: lib/l10n\n',
      });

      expect(_facts(project), (
        flutter: false,
        fvm: false,
        codegen: false,
        l10n: true,
        assets: false,
      ));
    });

    test('detects l10n from an l10n.yaml file in a nested package', () async {
      final project = await _detect({
        'pubspec.yaml': _pureDart,
        'packages/app/l10n.yaml': 'arb-dir: lib/l10n\n',
      });

      expect(project.usesL10n, isTrue);
    });

    test('ignores a file whose name only ends in l10n.yaml', () async {
      final project = await _detect({
        'pubspec.yaml': _pureDart,
        'tool/old_l10n.yaml': 'arb-dir: lib/l10n\n',
      });

      expect(project.usesL10n, isFalse);
    });

    test('detects assets from a flutter assets section', () async {
      final project = await _detect({
        'pubspec.yaml': '''
name: app
flutter:
  assets:
    - assets/images/
''',
      });

      expect(_facts(project), (
        flutter: false,
        fvm: false,
        codegen: false,
        l10n: false,
        assets: true,
      ));
    });

    test('ignores a flutter section without assets', () async {
      final project = await _detect({
        'pubspec.yaml': '''
name: app
flutter:
  uses-material-design: true
''',
      });

      expect(project.usesAssets, isFalse);
    });

    test('ignores a pubspec that cannot be parsed', () async {
      final project = await _detect({
        'pubspec.yaml': 'dev_dependencies: [build_runner\n',
      });

      expect(_facts(project), _nothing);
    });

    test('reports every fact of a full Flutter project', () async {
      final project = await _detect({
        'pubspec.yaml': '''
name: app
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  build_runner: ^2.4.0
flutter:
  assets:
    - assets/
''',
        '.fvmrc': '{"flutter": "3.38.0"}\n',
        'l10n.yaml': 'arb-dir: lib/l10n\n',
      });

      expect(_facts(project), (
        flutter: true,
        fvm: true,
        codegen: true,
        l10n: true,
        assets: true,
      ));
    });
  });
}

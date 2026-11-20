import 'package:stagelatch/src/checks/assets/asset_declarations.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

AssetDeclarations _declarations(
  String flutterSection, {
  String pubspecPath = 'pubspec.yaml',
}) {
  final yaml = 'name: app\nflutter:\n$flutterSection';
  final result = const StructuredDocuments().parseYaml(
    yaml,
    RepoPath(pubspecPath),
  );
  return AssetDeclarations.fromPubspec(
    PubspecDocument((result as DocumentParsed).root as LocatedMap),
    RepoPath(pubspecPath),
  );
}

AssetDeclarations _assets(List<String> entries, {String? pubspecPath}) =>
    _declarations(
      '  assets:\n${[for (final e in entries) '    - $e\n'].join()}',
      pubspecPath: pubspecPath ?? 'pubspec.yaml',
    );

void main() {
  test('a file is declared by exact path or by its directory, not '
      'recursively', () {
    final d = _assets(['assets/img/', 'assets/data/config.json']);

    expect(d.declares(RepoPath('assets/img/a.png')), isTrue);
    expect(d.declares(RepoPath('assets/img/icons/b.png')), isFalse);
    expect(d.declares(RepoPath('assets/data/config.json')), isTrue);
    expect(d.declares(RepoPath('assets/data/other.json')), isFalse);
  });

  test('a directory entry does not declare a file named like the directory '
      'without a slash', () {
    final d = _assets(['assets/img']);

    expect(d.declares(RepoPath('assets/img/a.png')), isFalse);
  });

  test('resolution variants are covered by their parent', () {
    expect(
      _assets(['assets/img/']).declares(RepoPath('assets/img/2.0x/a.png')),
      isTrue,
    );
    expect(
      _assets(['assets/img/a.png']).declares(RepoPath('assets/img/3.0x/a.png')),
      isTrue,
    );
    expect(
      _assets(['assets/img/a.png'])
          .declares(RepoPath('assets/img/3.0x/other.png')),
      isFalse,
    );
  });

  test('a variant directory is a number, an optional fraction and x', () {
    final d = _assets(['assets/img/']);

    for (final variant in ['1x', '2.0x', '1.5x', '12x']) {
      expect(d.declares(RepoPath('assets/img/$variant/a.png')), isTrue);
    }
    for (final other in ['x', '2.x', '.5x', 'dark', '2.0', 'a2x']) {
      expect(d.declares(RepoPath('assets/img/$other/a.png')), isFalse);
    }
  });

  test('fonts listed under flutter: fonts are declared', () {
    final d = _declarations('''
  fonts:
    - family: Brand
      fonts:
        - asset: fonts/Brand-Regular.ttf
        - asset: fonts/Brand-Bold.ttf
          weight: 700
''');

    expect(d.declares(RepoPath('fonts/Brand-Regular.ttf')), isTrue);
    expect(d.declares(RepoPath('fonts/Brand-Bold.ttf')), isTrue);
    expect(d.declares(RepoPath('fonts/Other.ttf')), isFalse);
    expect(d.entries.map((e) => e.entry), [
      'fonts/Brand-Regular.ttf',
      'fonts/Brand-Bold.ttf',
    ]);
  });

  test('an asset written as a map with a path is declared', () {
    final d = _declarations('''
  assets:
    - path: assets/data/
      flavors:
        - prod
    - path: assets/logo.png
''');

    expect(d.declares(RepoPath('assets/data/a.json')), isTrue);
    expect(d.declares(RepoPath('assets/logo.png')), isTrue);
  });

  test('entries keep their order, kind and location', () {
    final d = _assets(['assets/img/', 'assets/data/config.json']);
    final entries = d.entries.toList();

    expect(entries.map((e) => e.entry), [
      'assets/img/',
      'assets/data/config.json',
    ]);
    expect(entries.map((e) => e.isDirectory), [true, false]);
    expect(entries.map((e) => e.path.value), [
      'assets/img',
      'assets/data/config.json',
    ]);
    // `    - assets/img/`: the scalar starts after the dash.
    expect(entries.first.location.start, const Position(4, 7));
  });

  test('paths are resolved against the directory of the pubspec', () {
    final d = _assets([
      'assets/img/',
      './assets/a.png',
    ], pubspecPath: 'packages/ui/pubspec.yaml');

    expect(d.declares(RepoPath('packages/ui/assets/img/a.png')), isTrue);
    expect(d.declares(RepoPath('packages/ui/assets/a.png')), isTrue);
    expect(d.declares(RepoPath('assets/img/a.png')), isFalse);
    expect(d.entries.map((e) => e.path.value), [
      'packages/ui/assets/img',
      'packages/ui/assets/a.png',
    ]);
  });

  test('an entry that climbs out of the repository declares nothing', () {
    final d = _assets(['../../outside/a.png', '../shared/']);

    expect(d.entries, isEmpty);
  });

  test('a pubspec with no flutter section, or a malformed one, declares '
      'nothing', () {
    expect(_declarations('  uses-material-design: true\n').entries, isEmpty);
    expect(_declarations('  assets: nope\n').entries, isEmpty);
    expect(_declarations('  assets:\n    - 3\n    - [a]\n').entries, isEmpty);
  });
}

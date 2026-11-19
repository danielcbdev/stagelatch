import 'dart:io';

import 'package:test/test.dart';

import 'module_rules.dart';

void main() {
  group('forbiddenImports', () {
    test('domain may not import dart:io or another module', () {
      expect(
        forbiddenImports(
          module: 'domain',
          imports: [
            'dart:io',
            'package:stagelatch/src/application/errors.dart',
            'package:meta/meta.dart',
          ],
        ),
        ['dart:io', 'package:stagelatch/src/application/errors.dart'],
      );
    });

    test('checks may import domain and pub_semver only', () {
      expect(
        forbiddenImports(
          module: 'checks',
          imports: [
            'package:stagelatch/src/domain/finding.dart',
            'package:pub_semver/pub_semver.dart',
            'package:yaml/yaml.dart',
          ],
        ),
        ['package:yaml/yaml.dart'],
      );
    });

    test('application may import checks but not infrastructure', () {
      expect(
        forbiddenImports(
          module: 'application',
          imports: [
            'package:stagelatch/src/checks/pubspec/pubspec_check.dart',
            'package:glob/glob.dart',
            'package:stagelatch/src/infrastructure/git/git_process.dart',
            'dart:io',
          ],
        ),
        [
          'package:stagelatch/src/infrastructure/git/git_process.dart',
          'dart:io',
        ],
      );
    });

    test('infrastructure may use any package but not checks or cli', () {
      expect(
        forbiddenImports(
          module: 'infrastructure',
          imports: [
            'dart:io',
            'package:yaml/yaml.dart',
            'package:stagelatch/src/application/errors.dart',
            'package:stagelatch/src/checks/pubspec/pubspec_check.dart',
            'package:stagelatch/src/cli/runner.dart',
          ],
        ),
        [
          'package:stagelatch/src/checks/pubspec/pubspec_check.dart',
          'package:stagelatch/src/cli/runner.dart',
        ],
      );
    });

    test('cli may import every module and the version file', () {
      expect(
        forbiddenImports(
          module: 'cli',
          imports: [
            'dart:io',
            'package:args/args.dart',
            'package:stagelatch/src/version.dart',
            'package:stagelatch/src/infrastructure/git/git_process.dart',
            'package:stagelatch/src/checks/pubspec/pubspec_check.dart',
          ],
        ),
        isEmpty,
      );
    });

    test('only cli may import the version file', () {
      expect(
        forbiddenImports(
          module: 'application',
          imports: ['package:stagelatch/src/version.dart'],
        ),
        ['package:stagelatch/src/version.dart'],
      );
    });

    test('nothing under lib/src may import the public barrel', () {
      expect(
        forbiddenImports(
          module: 'cli',
          imports: ['package:stagelatch/stagelatch.dart'],
        ),
        ['package:stagelatch/stagelatch.dart'],
      );
    });

    test('an unresolved relative import is forbidden', () {
      expect(forbiddenImports(module: 'domain', imports: ['finding.dart']), [
        'finding.dart',
      ]);
    });

    test('a directory that is not in the module table is rejected', () {
      expect(
        () => forbiddenImports(module: 'utils', imports: const []),
        throwsArgumentError,
      );
    });
  });

  group('directiveUris', () {
    test('reads import, export and part URIs in source order', () {
      const source = '''
import 'dart:async';
import "package:meta/meta.dart" show immutable;
export 'src/version.dart';
part 'a.g.dart';

class A {}
''';
      expect(directiveUris(source), [
        'dart:async',
        'package:meta/meta.dart',
        'src/version.dart',
        'a.g.dart',
      ]);
    });

    test('reads every branch of a conditional import', () {
      const source = '''
import 'stub.dart'
    if (dart.library.io) 'io.dart'
    if (dart.library.html) 'web.dart';
''';
      expect(directiveUris(source), ['stub.dart', 'io.dart', 'web.dart']);
    });

    test('ignores directives inside line comments', () {
      const source = '''
// import 'dart:io';
/// import 'dart:mirrors';
import 'dart:core';
''';
      expect(directiveUris(source), ['dart:core']);
    });
  });

  group('normalizeUri', () {
    test('resolves a relative URI against the importing file', () {
      expect(
        normalizeUri(
          '../../domain/finding.dart',
          importer: 'lib/src/checks/pubspec/pubspec_check.dart',
        ),
        'package:stagelatch/src/domain/finding.dart',
      );
    });

    test('keeps dart: and package: URIs unchanged', () {
      expect(
        normalizeUri('dart:io', importer: 'lib/src/cli/runner.dart'),
        'dart:io',
      );
      expect(
        normalizeUri(
          'package:args/args.dart',
          importer: 'lib/src/cli/runner.dart',
        ),
        'package:args/args.dart',
      );
    });
  });

  group('moduleOfFile', () {
    test('is the first directory under lib/src', () {
      expect(moduleOfFile('lib/src/domain/dart/import_graph.dart'), 'domain');
      expect(moduleOfFile('lib/src/cli/commands/run_command.dart'), 'cli');
    });

    test('is root for a file directly under lib/src', () {
      expect(moduleOfFile('lib/src/version.dart'), 'root');
    });
  });

  test('nothing imports package:analyzer or package:dart_style (ADR-0008)', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          for (final uri in directiveUris(file.readAsStringSync()))
            if (uri.startsWith('package:analyzer/') ||
                uri.startsWith('package:dart_style/'))
              '${file.path}: $uri',
    ];

    expect(offenders, isEmpty);
  });

  test(
    'only infrastructure/dart starts the analysis server or dart format',
    () {
      final dartDir = [
        'lib',
        'src',
        'infrastructure',
        'dart',
      ].join(Platform.pathSeparator);
      final offenders = [
        for (final file in Directory('lib').listSync(recursive: true))
          if (file is File &&
              file.path.endsWith('.dart') &&
              !file.path.contains(dartDir))
            if (_spawnsDartTool(file.readAsStringSync())) file.path,
      ];

      expect(offenders, isEmpty);
    },
  );

  test('every file under lib/src obeys the module table', () {
    final violations = <String>[];
    final files = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      // Windows lists paths with backslashes; the rules use forward slashes.
      final path = file.path.replaceAll(r'\', '/');
      final imports = directiveUris(file.readAsStringSync())
          .map((uri) => normalizeUri(uri, importer: path));
      final forbidden = forbiddenImports(
        module: moduleOfFile(path),
        imports: imports,
      );
      violations.addAll(forbidden.map((uri) => '$path imports $uri'));
    }
    expect(violations, isEmpty);
  });
}

/// Whether [source] starts the analysis server or `dart format`.
bool _spawnsDartTool(String source) =>
    source.contains("'language-server'") ||
    (source.contains('Process.') && source.contains("'format'"));

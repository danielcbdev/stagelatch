import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/test_command.dart';
import 'package:test/test.dart';

ResolvedSdk sdk({String? flutter = '/flutter/bin/flutter'}) => ResolvedSdk(
  root: '/sdk',
  dartExecutable: '/sdk/bin/dart',
  flutterExecutable: flutter,
  version: '3.13.4',
  source: SdkSource.path,
);

DartPackage package({String? root = 'packages/ui', bool flutter = false}) =>
    DartPackage(
      root: root == null ? null : RepoPath(root),
      name: 'ui',
      usesFlutter: flutter,
    );

List<TestCommand> commands(
  List<String> files, {
  DartPackage? pkg,
  ResolvedSdk? resolved,
}) => testCommands(
  sdk: resolved ?? sdk(),
  package: pkg ?? package(),
  files: [for (final file in files) RepoPath(file)],
);

/// The number of characters the files of [command] add to its arguments.
int fileCharacters(TestCommand command) => command.arguments
    .skipWhile((argument) => argument != '--')
    .skip(1)
    .fold<int>(0, (sum, argument) => sum + argument.length + 1);

void main() {
  group('testCommands', () {
    test('a Dart package runs dart test with the json reporter in its '
        'directory, files relative to it', () {
      final command = commands(['packages/ui/test/a_test.dart']).single;

      expect(command.executable, '/sdk/bin/dart');
      expect(command.arguments, [
        '--suppress-analytics',
        'test',
        '--reporter',
        'json',
        '--',
        'test/a_test.dart',
      ]);
      expect(command.directory, RepoPath('packages/ui'));
    });

    test('a package at the repository root has no directory and keeps the '
        'paths', () {
      final command = commands([
        'test/a_test.dart',
      ], pkg: package(root: null)).single;

      expect(command.directory, isNull);
      expect(command.arguments.last, 'test/a_test.dart');
    });

    test('a Flutter package runs flutter test --machine', () {
      final command = commands([
        'packages/ui/test/a_test.dart',
      ], pkg: package(flutter: true)).single;

      expect(command.executable, '/flutter/bin/flutter');
      expect(command.arguments, [
        'test',
        '--machine',
        '--',
        'test/a_test.dart',
      ]);
      expect(command.directory, RepoPath('packages/ui'));
    });

    test('a Flutter package without a flutter executable is a state '
        'error', () {
      expect(
        () => commands(
          ['packages/ui/test/a_test.dart'],
          pkg: package(flutter: true),
          resolved: sdk(flutter: null),
        ),
        throwsStateError,
      );
    });

    test('files are sorted by path', () {
      final command = commands([
        'packages/ui/test/b_test.dart',
        'packages/ui/test/a_test.dart',
        'packages/ui/test/a/c_test.dart',
      ]).single;

      expect(command.arguments.skip(5), [
        'test/a/c_test.dart',
        'test/a_test.dart',
        'test/b_test.dart',
      ]);
    });

    test('a path with a space stays one argument', () {
      final command = commands(['packages/ui/test/a b_test.dart']).single;

      expect(command.arguments.last, 'test/a b_test.dart');
    });

    test('no file means no command', () {
      expect(commands(const []), isEmpty);
    });

    test('a file outside the package is an argument error', () {
      expect(
        () => commands(['packages/other/test/a_test.dart']),
        throwsArgumentError,
      );
    });

    test('files are batched at 20,000 characters in path order and nothing '
        'is lost or reordered', () {
      final files = [
        for (var i = 0; i < 300; i++)
          'packages/ui/test/${i.toString().padLeft(4, '0')}_${'x' * 80}.dart',
      ];

      final batches = commands(files.reversed.toList());

      expect(batches.length, greaterThan(1));
      for (final batch in batches) {
        expect(fileCharacters(batch), lessThanOrEqualTo(20000));
      }
      final run = [
        for (final batch in batches)
          for (final argument in batch.arguments.skip(5))
            'packages/ui/$argument',
      ];
      expect(run, files);
    });

    test('a batch that fills 20,000 characters exactly is not split', () {
      // Each file counts its length plus one separator: 100 files of 199
      // characters are exactly 20,000.
      final files = [
        for (var i = 0; i < 100; i++)
          'packages/ui/${i.toString().padLeft(3, '0')}${'x' * 191}.dart',
      ];
      final relative = files.first.substring('packages/ui/'.length);
      expect(relative.length + 1, 200);

      expect(commands(files), hasLength(1));
      expect(commands([...files, 'packages/ui/zzz_test.dart']), hasLength(2));
    });

    test('a single path longer than the limit is its own batch', () {
      final long = 'packages/ui/test/${'y' * 25000}.dart';

      final batches = commands([
        'packages/ui/test/a_test.dart',
        long,
        'packages/ui/test/z_test.dart',
      ]);

      expect(batches.map((batch) => batch.arguments.skip(5).length), [1, 1, 1]);
      expect(batches[1].arguments.last, 'test/${'y' * 25000}.dart');
    });
  });
}

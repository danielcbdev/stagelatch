/// The command lines that run test files (docs/specs/dart-toolchain.md,
/// section 6, security S14).
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// The most characters of test file arguments one process gets: each path
/// counts its length plus one for the separator. Far below the shortest
/// command line limit of the platforms the tool runs on.
const _maxFileCharacters = 20000;

/// One process to start.
@immutable
final class TestCommand {
  /// Creates a command.
  const new({
    required this.executable,
    required this.arguments,
    required this.directory,
  });

  /// The SDK executable: `dart` or `flutter`.
  final String executable;

  /// The arguments, test files last, after `--`.
  final List<String> arguments;

  /// The package root, relative to the repository root, where the process
  /// runs; null for a package at the repository root.
  final RepoPath? directory;

  /// The test files of this command, as passed: relative to [directory].
  List<String> get files => arguments.sublist(arguments.indexOf('--') + 1);

  @override
  String toString() => '$executable ${arguments.join(' ')}';
}

/// The commands that run [files] of [package], one per batch, in path order.
///
/// A Dart package runs `dart test --reporter json`, a Flutter package
/// `flutter test --machine`. The files are repository paths inside
/// [package]; they are passed relative to its directory, after `--`, and
/// split into batches of at most 20,000 characters (a single longer path is a
/// batch of its own). Nothing is lost, repeated or reordered.
///
/// Throws [StateError] for a Flutter package when [sdk] has no flutter
/// executable, and [ArgumentError] for a file outside [package].
List<TestCommand> testCommands({
  required ResolvedSdk sdk,
  required DartPackage package,
  required List<RepoPath> files,
}) {
  if (files.isEmpty) return const [];
  final String executable;
  final List<String> fixed;
  if (package.usesFlutter) {
    final flutter = sdk.flutterExecutable;
    if (flutter == null) {
      throw StateError('The resolved SDK has no flutter executable.');
    }
    executable = flutter;
    fixed = const ['test', '--machine', '--'];
  } else {
    executable = sdk.dartExecutable;
    fixed = const [
      // The gate never touches the network (ADR-0003).
      '--suppress-analytics',
      'test',
      '--reporter',
      'json',
      '--',
    ];
  }

  final root = package.root;
  final sorted = {...files}.toList()..sort();
  final relative = [
    for (final file in sorted)
      if (root == null)
        file.value
      else if (file.isWithin(root))
        file.value.substring(root.value.length + 1)
      else
        throw ArgumentError.value(
          file.value,
          'files',
          'is not inside the package at ${root.value}',
        ),
  ];

  final commands = <TestCommand>[];
  var batch = <String>[];
  var characters = 0;
  void flush() {
    if (batch.isEmpty) return;
    commands.add(
      TestCommand(
        executable: executable,
        arguments: List.unmodifiable([...fixed, ...batch]),
        directory: root,
      ),
    );
    batch = [];
    characters = 0;
  }

  for (final path in relative) {
    final cost = path.length + 1;
    if (batch.isNotEmpty && characters + cost > _maxFileCharacters) flush();
    batch.add(path);
    characters += cost;
  }
  flush();
  return commands;
}

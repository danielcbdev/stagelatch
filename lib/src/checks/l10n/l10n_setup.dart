/// Where a package keeps its translations (`l10n.yaml`).
library;

import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

const _defaultArbDir = 'lib/l10n';
const _defaultTemplate = 'app_en.arb';

/// The localization settings of one package, with every directory resolved
/// to a repository path.
final class L10nSetup {
  /// Creates a setup.
  const new({required this.arbDir, required this.templateFile, this.outputDir});

  /// The directory that holds the `.arb` files.
  final RepoPath arbDir;

  /// The name of the template `.arb` file inside [arbDir].
  final String templateFile;

  /// The directory Flutter writes the generated localizations to, when
  /// `l10n.yaml` names one.
  final RepoPath? outputDir;
}

/// Reads the `l10n.yaml` beside the pubspec of [package] from [files].
///
/// A package without `l10n.yaml` does not use `gen_l10n`, so there is
/// nothing to check and the result is null. So is an `l10n.yaml` that is
/// not a YAML map, or that names a directory outside the package: a rule
/// must not guess what Flutter would do with them. An empty file is valid
/// and means every default. A value that is not a string is ignored, as
/// Flutter would reject it itself.
Future<L10nSetup?> readL10nSetup(
  SnapshotFiles files,
  Documents documents,
  DartPackage package,
) async {
  final root = package.root?.value;
  final path = RepoPath(root == null ? 'l10n.yaml' : '$root/l10n.yaml');
  final parsed = await documents.yaml(files, path);
  if (parsed is! DocumentParsed) return null;

  final Map<String, LocatedEntry> keys;
  switch (parsed.root) {
    case LocatedMap(:final entries):
      keys = entries;
    case LocatedScalar(value: null):
      keys = const {};
    default:
      return null;
  }

  String? text(String key) => switch (keys[key]?.value) {
    LocatedScalar(:final String value) => value,
    _ => null,
  };

  final arbDir = _resolve(root, text('arb-dir') ?? _defaultArbDir);
  if (arbDir == null) return null;
  final outputText = text('output-dir');
  final outputDir = outputText == null ? null : _resolve(root, outputText);
  if (outputText != null && outputDir == null) return null;
  return L10nSetup(
    arbDir: arbDir,
    templateFile: text('template-arb-file') ?? _defaultTemplate,
    outputDir: outputDir,
  );
}

/// [directory] resolved against the package directory [root] (null for the
/// repository root), as plain text arithmetic. Null when it is absolute,
/// climbs out of the package, or names the package itself.
RepoPath? _resolve(String? root, String directory) {
  if (directory.startsWith('/') || directory.contains(r'\')) return null;
  final segments = <String>[];
  for (final segment in directory.split('/')) {
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (segments.isEmpty) return null;
        segments.removeLast();
      default:
        segments.add(segment);
    }
  }
  if (segments.isEmpty) return null;
  return RepoPath([?root, ...segments].join('/'));
}

/// What `stagelatch init` can see in a repository.
library;

import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// The facts that change which checks `init` enables.
final class DetectedProject {
  /// Creates the facts.
  const new({
    required this.usesFlutter,
    required this.usesFvm,
    required this.usesCodegen,
    required this.usesL10n,
    required this.usesAssets,
  });

  /// A pubspec depends on the Flutter SDK.
  final bool usesFlutter;

  /// `.fvmrc` or `.fvm/` is present.
  final bool usesFvm;

  /// `build_runner` is a dev dependency.
  final bool usesCodegen;

  /// An `l10n.yaml` is present.
  final bool usesL10n;

  /// A pubspec has a `flutter: assets:` section.
  final bool usesAssets;
}

/// Reads the snapshot once and reports [DetectedProject].
final class ProjectDetector {
  /// Creates a detector over the snapshot and the document parser.
  const new(this._files, this._documents);

  final SnapshotFiles _files;
  final Documents _documents;

  /// Detects the project from the snapshot.
  Future<DetectedProject> detect() async {
    final entries = await _files.list();
    final paths = [for (final entry in entries) entry.path.value];
    var flutter = false;
    var codegen = false;
    var assets = false;
    for (final entry in entries) {
      if (entry.path.basename != 'pubspec.yaml') continue;
      final document = await _documents.yaml(_files, entry.path);
      if (document case DocumentParsed(:final LocatedMap root)) {
        flutter = flutter || _usesFlutter(root);
        codegen = codegen || _usesCodegen(root);
        assets = assets || _usesAssets(root);
      }
    }
    return DetectedProject(
      usesFlutter: flutter,
      usesFvm: paths.any(
        (path) => path == '.fvmrc' || path.startsWith('.fvm/'),
      ),
      usesCodegen: codegen,
      usesL10n: paths.any((path) => path.endsWith('l10n.yaml')),
      usesAssets: assets,
    );
  }
}

bool _usesFlutter(LocatedMap root) {
  for (final section in ['dependencies', 'dev_dependencies']) {
    if (root.entries[section]?.value case LocatedMap(:final entries)) {
      if (entries['flutter']?.value case LocatedMap(:final entries)) {
        if (entries['sdk']?.value case LocatedScalar(value: 'flutter')) {
          return true;
        }
      }
    }
  }
  return false;
}

bool _usesCodegen(LocatedMap root) {
  if (root.entries['dev_dependencies']?.value case LocatedMap(:final entries)) {
    return entries.containsKey('build_runner');
  }
  return false;
}

bool _usesAssets(LocatedMap root) {
  if (root.entries['flutter']?.value case LocatedMap(:final entries)) {
    return entries.containsKey('assets');
  }
  return false;
}

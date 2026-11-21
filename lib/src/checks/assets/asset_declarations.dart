/// What a pubspec declares as assets (docs/specs/rules.md, `assets`).
library;

import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// A resolution variant directory: a number, an optional fraction, then
/// `x`, as in `2.0x`. Anchored and linear in the length of the name
/// (security rule S6).
final _variant = RegExp(r'^\d+(\.\d+)?x$');

/// Whether [directoryName] names a resolution variant such as `2.0x`.
bool isResolutionVariant(String directoryName) =>
    _variant.hasMatch(directoryName);

/// One entry of `flutter: assets:` or one font file of `flutter: fonts:`.
final class DeclaredAsset {
  /// Creates a declared asset.
  const new({
    required this.entry,
    required this.path,
    required this.isDirectory,
    required this.location,
  });

  /// The entry as written, such as `assets/img/`.
  final String entry;

  /// The repository path the entry names, resolved against the directory of
  /// the pubspec. For a directory, without the trailing slash.
  final RepoPath path;

  /// Whether the entry ends with a slash, which declares the files directly
  /// inside the directory.
  final bool isDirectory;

  /// Where the entry is written in `pubspec.yaml`.
  final Location location;
}

/// The assets a pubspec declares, and the question "is this file one?".
///
/// As in Flutter, a directory entry declares the files directly inside it
/// and is not recursive; a file in a resolution variant directory (`2.0x`)
/// is declared by what declares its counterpart one level up; and the font
/// files under `flutter: fonts:` are declared.
final class AssetDeclarations {
  const new _(this.entries, this._files, this._directories);

  /// Reads the declarations of [document], the pubspec at [pubspecPath].
  ///
  /// It never throws on an unexpected shape: an entry that is not a string
  /// (or a map with a `path`) is ignored, and so is one that resolves
  /// outside the repository.
  factory fromPubspec(PubspecDocument document, RepoPath pubspecPath) {
    final base = pubspecPath.parent?.value;
    final entries = <DeclaredAsset>[];

    void add(String entry, Location location) {
      final resolved = _resolve(base, entry);
      if (resolved == null) return;
      entries.add(
        DeclaredAsset(
          entry: entry,
          path: resolved,
          isDirectory: entry.endsWith('/'),
          location: location,
        ),
      );
    }

    if (document.root.entries['flutter']?.value case LocatedMap(
      entries: final flutter,
    )) {
      if (flutter['assets']?.value case LocatedList(:final items)) {
        for (final item in items) {
          switch (item) {
            case LocatedScalar(value: final String entry, :final location):
              add(entry, location);
            case LocatedMap(entries: final fields):
              if (fields['path']?.value case LocatedScalar(
                value: final String entry,
                :final location,
              )) {
                add(entry, location);
              }
            default:
              break;
          }
        }
      }
      if (flutter['fonts']?.value case LocatedList(items: final families)) {
        for (final family in families) {
          if (family case LocatedMap(entries: final familyFields)) {
            if (familyFields['fonts']?.value case LocatedList(
              items: final fonts,
            )) {
              for (final font in fonts) {
                if (font case LocatedMap(entries: final fontFields)) {
                  if (fontFields['asset']?.value case LocatedScalar(
                    value: final String entry,
                    :final location,
                  )) {
                    add(entry, location);
                  }
                }
              }
            }
          }
        }
      }
    }
    return AssetDeclarations._(
      List.unmodifiable(entries),
      {
        for (final entry in entries)
          if (!entry.isDirectory) entry.path,
      },
      {
        for (final entry in entries)
          if (entry.isDirectory) entry.path,
      },
    );
  }

  /// Every declared entry, in document order: assets first, then fonts.
  final Iterable<DeclaredAsset> entries;

  final Set<RepoPath> _files;
  final Set<RepoPath> _directories;

  /// Whether [file], a repository path, is declared.
  bool declares(RepoPath file) {
    if (_files.contains(file)) return true;
    final parent = file.parent;
    if (parent == null) return false;
    if (_directories.contains(parent)) return true;
    if (!isResolutionVariant(parent.basename)) return false;
    // `dir/2.0x/name` is a variant of `dir/name`, and lives in `dir`.
    final dir = parent.parent;
    if (dir == null) return _files.contains(RepoPath(file.basename));
    return _directories.contains(dir) ||
        _files.contains(RepoPath('${dir.value}/${file.basename}'));
  }
}

/// [entry] resolved against the directory [base] (null for the repository
/// root), as plain text arithmetic. Null when it climbs above the root or
/// names the root itself.
RepoPath? _resolve(String? base, String entry) {
  final segments = [...?base?.split('/')];
  for (final segment in entry.replaceAll(r'\', '/').split('/')) {
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
  return RepoPath(segments.join('/'));
}

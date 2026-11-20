/// The `assets` check.
library;

import 'package:stagelatch/src/checks/assets/asset_declarations.dart';
import 'package:stagelatch/src/checks/assets/assets_rules.dart';
import 'package:stagelatch/src/checks/assets/assets_settings.dart';
import 'package:stagelatch/src/checks/assets/format_size.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

const _pubspecFileName = 'pubspec.yaml';

/// Compares the assets a pubspec declares with the files of its package
/// (docs/specs/rules.md, `assets`).
///
/// A pubspec is looked at when it changed, or when an asset of its package
/// changed or was deleted: a deleted file leaves its declaration pointing
/// at nothing. For such a pubspec every declaration is checked for
/// existence, and every changed file under an asset root is checked against
/// the declarations and the size limit. A file that did not change is not
/// this change's to answer for.
final class AssetsCheck implements Check {
  /// Creates the check.
  const new();

  @override
  String get id => assetsCheckId;

  @override
  CheckPhase get phase => CheckPhase.verify;

  @override
  List<RuleDescriptor> get rules => assetsRuleDescriptors;

  @override
  bool get hasDynamicRules => false;

  @override
  Future<CheckResult> run(CheckContext context) async {
    final wantMissing = context.isEnabled(missingRule);
    final wantUndeclared = context.isEnabled(undeclaredRule);
    final wantSize = context.isEnabled(maxFileSizeRule);
    if (!wantMissing && !wantUndeclared && !wantSize) {
      return const CheckResult();
    }
    final settings = context.settings<AssetsSettings>();

    // Pubspec -> the changed files of its package that sit under a root.
    final work = <RepoPath, Set<RepoPath>>{};
    for (final change in context.changes.changes) {
      final path = change.path;
      if (path.basename == _pubspecFileName) {
        if (change.kind != ChangeKind.deleted) work.putIfAbsent(path, () => {});
        continue;
      }
      final package = context.packages.packageOf(path);
      if (package == null) continue;
      final relative = _within(package.root, path);
      if (_rootOf(settings, relative) == null || _ignored(settings, relative)) {
        continue;
      }
      final files = work.putIfAbsent(_pubspecOf(package), () => {});
      if (change.kind != ChangeKind.deleted) files.add(path);
    }

    final findings = <Finding>[];
    for (final pubspecPath in work.keys.toList()..sort()) {
      final parsed = await context.documents.yaml(
        context.snapshot,
        pubspecPath,
      );
      // A pubspec that cannot be read is the `pubspec` check's to report.
      if (parsed is! DocumentParsed || parsed.root is! LocatedMap) continue;
      final declarations = AssetDeclarations.fromPubspec(
        PubspecDocument(parsed.root as LocatedMap),
        pubspecPath,
      );
      final packageDir = pubspecPath.parent;

      if (wantMissing) {
        for (final asset in declarations.entries) {
          final relative = _within(packageDir, asset.path);
          if (_ignored(settings, relative, directory: asset.isDirectory)) {
            continue;
          }
          if (!await _exists(context.snapshot, asset)) {
            findings.add(
              Finding(
                rule: missingRule,
                severity: Severity.error,
                message:
                    'Asset "${asset.entry}" is declared but does not exist.',
                location: asset.location,
              ),
            );
          }
        }
      }

      for (final file in work[pubspecPath]!.toList()..sort()) {
        final entry = await context.snapshot.entry(file);
        if (entry == null || !entry.mode.isFile) continue;
        final relative = _within(packageDir, file);
        final root = _rootOf(settings, relative)!;
        if (wantUndeclared && !declarations.declares(file)) {
          findings.add(
            Finding(
              rule: undeclaredRule,
              severity: Severity.error,
              message:
                  'File is under "${root.value}/" but is not declared in '
                  '$_pubspecFileName.',
              location: Location.wholeFile(file),
            ),
          );
        }
        if (wantSize) {
          final size = await context.snapshot.size(file);
          if (size != null && size > settings.maxFileSize) {
            findings.add(
              Finding(
                rule: maxFileSizeRule,
                severity: Severity.error,
                message:
                    'File is ${formatSize(size, limit: settings.maxFileSize)}, '
                    'larger than the limit of '
                    '${formatLimit(settings.maxFileSize)}.',
                location: Location.wholeFile(file),
              ),
            );
          }
        }
      }
    }
    return CheckResult(findings: findings);
  }

  /// Whether the declared [asset] is in [snapshot]: the file itself, or at
  /// least one file directly in the directory or in one of its resolution
  /// variant directories.
  Future<bool> _exists(SnapshotFiles snapshot, DeclaredAsset asset) async {
    if (!asset.isDirectory) return await snapshot.entry(asset.path) != null;
    for (final entry in await snapshot.list(under: asset.path)) {
      final parent = entry.path.parent;
      if (parent == null) continue;
      if (parent == asset.path) return true;
      if (parent.parent == asset.path && isResolutionVariant(parent.basename)) {
        return true;
      }
    }
    return false;
  }
}

/// The pubspec of [package].
RepoPath _pubspecOf(DartPackage package) {
  final root = package.root;
  return root == null
      ? RepoPath(_pubspecFileName)
      : RepoPath('${root.value}/$_pubspecFileName');
}

/// [path] relative to [directory], which is null for the repository root.
/// A path that is not inside [directory] (an entry that climbs out of its
/// package) is returned whole.
String _within(RepoPath? directory, RepoPath path) {
  if (directory == null) return path.value;
  final prefix = '${directory.value}/';
  return path.value.startsWith(prefix)
      ? path.value.substring(prefix.length)
      : path.value;
}

/// The root of [settings] that holds [relative], a path inside a package.
RepoPath? _rootOf(AssetsSettings settings, String relative) {
  for (final root in settings.roots) {
    if (relative.startsWith('${root.value}/')) return root;
  }
  return null;
}

/// Whether `assets.ignore` leaves [relative] alone. A directory is also
/// ignored when something inside it would be, because `assets/videos/**`
/// does not match `assets/videos` itself.
bool _ignored(
  AssetsSettings settings,
  String relative, {
  bool directory = false,
}) => settings.ignore.any(
  (matches) => matches(relative) || (directory && matches('$relative/x')),
);

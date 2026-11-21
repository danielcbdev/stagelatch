/// The `pubspec` check.
library;

import 'package:stagelatch/src/checks/pubspec/build_number_regression.dart';
import 'package:stagelatch/src/checks/pubspec/dependency_overrides.dart';
import 'package:stagelatch/src/checks/pubspec/lockfile_document.dart';
import 'package:stagelatch/src/checks/pubspec/lockfile_out_of_sync.dart';
import 'package:stagelatch/src/checks/pubspec/path_dependency.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_document.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_rules.dart';
import 'package:stagelatch/src/checks/pubspec/pubspec_settings.dart';
import 'package:stagelatch/src/checks/pubspec/unpinned_git.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// Inspects every `pubspec.yaml` and `pubspec_overrides.yaml` of the
/// changeset (docs/specs/rules.md, `pubspec`).
///
/// A pubspec that did not change is never opened: a problem that was
/// already committed is not this change's to answer for.
final class PubspecCheck implements Check {
  /// Creates the check.
  const new();

  @override
  String get id => pubspecCheckId;

  @override
  CheckPhase get phase => CheckPhase.verify;

  @override
  List<RuleDescriptor> get rules => pubspecRuleDescriptors;

  @override
  bool get hasDynamicRules => false;

  @override
  Future<CheckResult> run(CheckContext context) async {
    final findings = <Finding>[];
    // Listing the snapshot is only worth it once a path rule needs it.
    Set<RepoPath>? pubspecsInSnapshot;
    PubspecSettings? settings;
    // Pubspecs whose lock was compared, and those whose lock changed.
    final lockCompared = <RepoPath>{};
    final lockChanged = <RepoPath>{};

    for (final change in context.changes.present) {
      final path = change.path;
      if (path.basename == pubspecOverridesFileName) {
        if (context.isEnabled(dependencyOverridesRule)) {
          findings.add(pubspecOverridesFileFinding(path));
        }
        continue;
      }
      if (path.basename == _lockFileName) {
        lockChanged.addAll(_pubspecsForLock(context, path));
        continue;
      }
      if (path.basename != pubspecFileName) continue;

      final parsed = await context.documents.yaml(context.snapshot, path);
      switch (parsed) {
        case DocumentMissing():
          // Present in the changeset, so this cannot happen for a real
          // snapshot; there is nothing to judge either way.
          continue;
        case DocumentInvalid(:final location, :final reason):
          _addUnparseable(context, findings, location, reason);
        case DocumentParsed(:final LocatedMap root):
          final document = PubspecDocument(root);
          if (context.isEnabled(pathDependencyRule)) {
            pubspecsInSnapshot ??= await _pubspecsOf(context);
            findings.addAll(
              pathDependencyFindings(document, path, pubspecsInSnapshot),
            );
          }
          if (context.isEnabled(dependencyOverridesRule)) {
            findings.addAll(dependencyOverridesFindings(document, path));
          }
          if (context.isEnabled(unpinnedGitRule)) {
            settings ??= context.settings<PubspecSettings>();
            findings.addAll(
              unpinnedGitFindings(
                document,
                path,
                requireSha: settings.requireSha,
              ),
            );
          }
          if (context.isEnabled(buildNumberRegressionRule)) {
            settings ??= context.settings<PubspecSettings>();
            findings.addAll(
              await _buildNumberFindings(context, change, document, settings),
            );
          }
          if (context.isEnabled(lockfileOutOfSyncRule)) {
            lockCompared.add(path);
            findings.addAll(await _lockfileFindings(context, path, document));
          }
        case DocumentParsed():
          _addUnparseable(
            context,
            findings,
            Location.wholeFile(path),
            'expected a map at the top level',
          );
      }
    }

    // A changed lock is compared with its pubspec even when the pubspec
    // did not change. A pubspec that cannot be read is not this rule's
    // business: `unparseable` reports it when it is the one that changed.
    if (context.isEnabled(lockfileOutOfSyncRule)) {
      for (final path in lockChanged.difference(lockCompared)) {
        final parsed = await context.documents.yaml(context.snapshot, path);
        if (parsed case DocumentParsed(:final LocatedMap root)) {
          findings.addAll(
            await _lockfileFindings(context, path, PubspecDocument(root)),
          );
        }
      }
    }
    return CheckResult(findings: findings);
  }

  /// `pubspec/build-number-regression` for one changed pubspec: only on a
  /// branch that must grow, and only when the base has a pubspec to compare
  /// with (at the previous path, for a rename).
  Future<List<Finding>> _buildNumberFindings(
    CheckContext context,
    FileChange change,
    PubspecDocument document,
    PubspecSettings settings,
  ) async {
    final branch = context.targetBranch;
    final base = context.base;
    if (branch == null ||
        base == null ||
        !settings.buildNumberMustGrowOn(branch)) {
      return const [];
    }
    final parsed = await context.documents.yaml(
      base,
      change.previousPath ?? change.path,
    );
    if (parsed case DocumentParsed(:final LocatedMap root)) {
      return buildNumberRegressionFindings(
        snapshot: document,
        base: PubspecDocument(root),
        path: change.path,
      );
    }
    return const [];
  }

  /// `pubspec/lockfile-out-of-sync` for the pubspec at [path]: silent when
  /// the snapshot has no lock at the package's resolution root, or one that
  /// is not a readable map.
  Future<List<Finding>> _lockfileFindings(
    CheckContext context,
    RepoPath path,
    PubspecDocument document,
  ) async {
    final package = context.packages.packageOf(path);
    final lockPath = package == null
        ? _sibling(path, _lockFileName)
        : _fileAt(context.packages.resolutionRootOf(package), _lockFileName);
    final parsed = await context.documents.yaml(context.snapshot, lockPath);
    if (parsed case DocumentParsed(:final LocatedMap root)) {
      final members = package == null
          ? const <String>{}
          : {
              for (final member in context.packages.workspaceMembersOf(package))
                member.name,
            };
      final isWorkspaceMember =
          package != null &&
          context.packages.workspaceRoots.containsKey(package);
      return lockfileFindings(
        pubspec: document,
        lock: LockfileDocument(root),
        pubspecPath: path,
        workspaceMemberNames: members,
        checkDirectUndeclared: !isWorkspaceMember,
      );
    }
    return const [];
  }

  /// Every pubspec that shares the lock at [lockPath]: the sibling for a
  /// lone package, every workspace member when it is a workspace root lock.
  Iterable<RepoPath> _pubspecsForLock(CheckContext context, RepoPath lockPath) {
    final package = context.packages.packageOf(lockPath);
    if (package == null) return [_sibling(lockPath, pubspecFileName)];
    final root = context.packages.resolutionPackageOf(package);
    if (context.packages.resolutionRootOf(package) != lockPath.parent &&
        !(lockPath.parent == null && root.root == null)) {
      // Lock is not at the resolution root: fall back to the sibling.
      return [_sibling(lockPath, pubspecFileName)];
    }
    return [
      for (final member in context.packages.workspaceMembersOf(root))
        _fileAt(member.root, pubspecFileName),
    ];
  }

  void _addUnparseable(
    CheckContext context,
    List<Finding> findings,
    Location location,
    String reason,
  ) {
    if (!context.isEnabled(unparseableRule)) return;
    findings.add(
      Finding(
        rule: unparseableRule,
        severity: Severity.error,
        message: '$pubspecFileName is not valid YAML: $reason.',
        location: location,
      ),
    );
  }

  /// Every `pubspec.yaml` of the snapshot: the packages a path dependency
  /// may legitimately point at.
  Future<Set<RepoPath>> _pubspecsOf(CheckContext context) async => {
    for (final entry in await context.snapshot.list())
      if (entry.path.basename == pubspecFileName) entry.path,
  };
}

/// The name `pub` gives the file that records resolved versions.
const String _lockFileName = 'pubspec.lock';

/// The file called [name] in the directory of [path].
RepoPath _sibling(RepoPath path, String name) {
  final parent = path.parent;
  return parent == null ? RepoPath(name) : RepoPath('${parent.value}/$name');
}

/// The file called [name] in [directory], or at the repository root when
/// [directory] is null.
RepoPath _fileAt(RepoPath? directory, String name) =>
    directory == null ? RepoPath(name) : RepoPath('${directory.value}/$name');

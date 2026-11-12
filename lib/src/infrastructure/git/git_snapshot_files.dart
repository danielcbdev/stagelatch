/// Snapshot content read from git.
library;

import 'dart:typed_data';

import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:stagelatch/src/infrastructure/git/cat_file_batch.dart';
import 'package:stagelatch/src/infrastructure/git/git_process.dart';
import 'package:stagelatch/src/infrastructure/git/name_status_parser.dart';

/// A snapshot backed by git: the index or the tree of one commit.
///
/// The listing (path, mode, blob id) is read once, on first use, and kept.
/// Content is then fetched by blob id through [CatFileBatch], so no path is
/// ever sent to git again. An instance is therefore a view of the snapshot
/// as it was when first used; open a new one after the index changes.
final class GitSnapshotFiles implements SnapshotFiles {
  /// Creates a view of the snapshot [_ref].
  new({required this._git, required this._batch, required this._ref});

  final GitProcess _git;
  final CatFileBatch _batch;
  final SnapshotRef _ref;

  Future<_Listing>? _listing;

  Future<_Listing> _load() => _listing ??= _read();

  Future<_Listing> _read() async {
    final entries = switch (_ref) {
      IndexSnapshot() => await _readIndex(),
      CommitSnapshot(:final sha) => await _readTree(sha),
    }..sort((a, b) => a.path.compareTo(b.path));
    return _Listing(List.unmodifiable(entries), {
      for (final entry in entries) entry.path: entry,
    });
  }

  /// Lists the index. Each record is `<mode> <blob id> <stage>\t<path>`.
  Future<List<SnapshotEntry>> _readIndex() async {
    // -s: print mode, blob id and stage, not just the path.
    // -z: NUL-terminated records, safe for any file name.
    final result = await _git.run(['ls-files', '-s', '-z']);
    return [
      for (final record in result.nulSeparated)
        _entry(record, modeAt: 0, idAt: 1, stageAt: 2),
    ];
  }

  /// Lists a commit. Each record is `<mode> <type> <object id>\t<path>`.
  Future<List<SnapshotEntry>> _readTree(String sha) async {
    // -r: recurse into subdirectories and list files only.
    // -z: NUL-terminated records, safe for any file name.
    final result = await _git.run(['ls-tree', '-r', '-z', sha]);
    return [
      for (final record in result.nulSeparated)
        _entry(record, modeAt: 0, idAt: 2),
    ];
  }

  SnapshotEntry _entry(
    String record, {
    required int modeAt,
    required int idAt,
    int? stageAt,
  }) {
    final tab = record.indexOf('\t');
    final fields = tab < 0
        ? const <String>[]
        : record.substring(0, tab).split(' ');
    if (fields.length != 3) {
      throw InternalException(
        'Unexpected entry in a git listing: $record',
        where: 'git',
      );
    }
    // A stage other than 0 is one side of an unresolved conflict.
    if (stageAt != null && fields[stageAt] != '0') {
      throw const UsageException(unmergedIndexMessage);
    }
    return SnapshotEntry(
      path: RepoPath(record.substring(tab + 1)),
      mode: _mode(fields[modeAt], record),
      blobId: fields[idAt],
    );
  }

  static FileMode _mode(String mode, String record) => switch (mode) {
    '100644' => FileMode.regular,
    '100755' => FileMode.executable,
    '120000' => FileMode.symlink,
    '160000' => FileMode.gitlink,
    _ => throw InternalException(
      'Unexpected file mode in a git listing: $record',
      where: 'git',
    ),
  };

  @override
  Future<SnapshotEntry?> entry(RepoPath path) async =>
      (await _load()).byPath[path];

  @override
  Future<List<SnapshotEntry>> list({RepoPath? under}) async {
    final all = (await _load()).sorted;
    if (under == null) return all;
    return [
      for (final entry in all)
        if (entry.path.isWithin(under)) entry,
    ];
  }

  @override
  Future<Uint8List?> readBytes(RepoPath path) async {
    final found = await entry(path);
    // A gitlink names a commit of another repository; there is no blob.
    if (found == null || found.mode == FileMode.gitlink) return null;
    return await _batch.read(found.blobId);
  }

  @override
  Future<String?> readText(RepoPath path) async {
    final found = await entry(path);
    if (found == null || !found.mode.isFile) return null;
    // Ask for the size first so that an oversized blob is never loaded.
    if (await _batch.size(found.blobId) > maxTextBytes) return null;
    return decodeSnapshotText(await _batch.read(found.blobId));
  }

  @override
  Future<int?> size(RepoPath path) async {
    final found = await entry(path);
    if (found == null || found.mode == FileMode.gitlink) return null;
    return await _batch.size(found.blobId);
  }
}

/// The entries of a snapshot, sorted and by path.
final class _Listing {
  const new(this.sorted, this.byPath);

  final List<SnapshotEntry> sorted;
  final Map<RepoPath, SnapshotEntry> byPath;
}

/// The read-only view of the content being judged.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// The largest file that [SnapshotFiles.readText] returns, in bytes: 5 MiB.
///
/// Repository content is untrusted input (security rule S6). No source,
/// manifest or translation file a rule inspects comes near this size, and
/// the limit keeps one huge file from exhausting memory in a commit hook.
const int maxTextBytes = 5 * 1024 * 1024;

/// How many leading bytes are inspected for a NUL to decide that content is
/// binary. This is the heuristic git itself uses.
const int _binaryProbeBytes = 8000;

/// Decodes the content of a snapshot file as text, or returns null when it
/// is not text a rule should read.
///
/// This is the single definition of the [SnapshotFiles.readText] contract:
/// null above [maxTextBytes], for content with a NUL among its first 8000
/// bytes, and for bytes that are not valid UTF-8. A leading byte order mark
/// is removed and line endings are returned as stored.
String? decodeSnapshotText(Uint8List bytes) {
  if (bytes.length > maxTextBytes) return null;
  final probe = bytes.length < _binaryProbeBytes
      ? bytes.length
      : _binaryProbeBytes;
  for (var index = 0; index < probe; index++) {
    if (bytes[index] == 0) return null;
  }
  try {
    final text = utf8.decode(bytes);
    return text.startsWith('﻿') ? text.substring(1) : text;
  } on FormatException {
    return null;
  }
}

/// The kind of an entry, from its git mode.
enum FileMode {
  /// An ordinary file (`100644`).
  regular,

  /// An executable file (`100755`).
  executable,

  /// A symbolic link (`120000`). Its content is the link target; it is
  /// never followed.
  symlink,

  /// A submodule (`160000`). It has no content in this repository.
  gitlink;

  /// Whether the entry is a file whose content rules may read.
  bool get isFile => this == regular || this == executable;
}

/// One entry of a snapshot.
@immutable
final class SnapshotEntry {
  /// Creates an entry.
  const new({required this.path, required this.mode, required this.blobId});

  /// Where the entry is.
  final RepoPath path;

  /// What kind of entry it is.
  final FileMode mode;

  /// The git object id of the content. Two entries with the same id have the
  /// same bytes, which makes it a cache key.
  final String blobId;

  @override
  bool operator ==(Object other) =>
      other is SnapshotEntry &&
      other.path == path &&
      other.mode == mode &&
      other.blobId == blobId;

  @override
  int get hashCode => Object.hash(path, mode, blobId);

  @override
  String toString() => '${mode.name} $blobId $path';
}

/// Read-only access to one snapshot: the index or a commit (ADR-0007).
///
/// This is the only way a check sees file content. It never reads the
/// working tree, which is what keeps unstaged edits out of the verdict
/// (ADR-0001).
abstract interface class SnapshotFiles {
  /// The entry at [path], or null when the snapshot has none.
  Future<SnapshotEntry?> entry(RepoPath path);

  /// Every entry, sorted by path; with [under], only entries inside that
  /// directory at any depth.
  Future<List<SnapshotEntry>> list({RepoPath? under});

  /// The raw content at [path], or null when the snapshot has no file there.
  Future<Uint8List?> readBytes(RepoPath path);

  /// The content at [path] decoded as UTF-8, with line endings as stored
  /// and a leading byte order mark removed.
  ///
  /// Null when there is no entry, when the entry is a symlink or gitlink,
  /// when the content is binary (a NUL byte in the first 8000 bytes), is
  /// not valid UTF-8, or is larger than [maxTextBytes].
  Future<String?> readText(RepoPath path);

  /// The size in bytes of the content at [path], without reading it, or
  /// null when the snapshot has no entry there.
  Future<int?> size(RepoPath path);
}

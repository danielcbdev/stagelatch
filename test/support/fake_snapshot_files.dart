import 'dart:convert';
import 'dart:typed_data';

import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// An in-memory [SnapshotFiles] that follows the port's contract.
final class FakeSnapshotFiles implements SnapshotFiles {
  /// Creates a snapshot from [files], keyed by path.
  ///
  /// A `String` value is stored as UTF-8 text and a `List<int>` value as
  /// raw bytes. [modes] overrides the mode of individual paths; every
  /// other entry is a regular file.
  new(Map<String, Object> files, {Map<String, FileMode> modes = const {}})
    : _content = {
        for (final MapEntry(:key, :value) in files.entries)
          RepoPath(key): switch (value) {
            final String text => Uint8List.fromList(utf8.encode(text)),
            final List<int> bytes => Uint8List.fromList(bytes),
            _ => throw ArgumentError.value(value, key, 'String or bytes'),
          },
      },
      _modes = {
        for (final MapEntry(:key, :value) in modes.entries)
          RepoPath(key): value,
      };

  final Map<RepoPath, Uint8List> _content;
  final Map<RepoPath, FileMode> _modes;

  @override
  Future<SnapshotEntry?> entry(RepoPath path) async {
    final bytes = _content[path];
    if (bytes == null) return null;
    return SnapshotEntry(
      path: path,
      mode: _modes[path] ?? FileMode.regular,
      blobId: _blobId(bytes),
    );
  }

  @override
  Future<List<SnapshotEntry>> list({RepoPath? under}) async {
    final paths =
        _content.keys
            .where((path) => under == null || path.isWithin(under))
            .toList()
          ..sort();
    return [for (final path in paths) (await entry(path))!];
  }

  @override
  Future<Uint8List?> readBytes(RepoPath path) async => _content[path];

  @override
  Future<String?> readText(RepoPath path) async {
    final bytes = _content[path];
    if (bytes == null) return null;
    if (!(_modes[path] ?? FileMode.regular).isFile) return null;
    if (bytes.length > maxTextBytes) return null;
    // Same heuristic as git: a NUL in the first 8000 bytes means binary.
    final probe = bytes.length < 8000 ? bytes.length : 8000;
    if (bytes.sublist(0, probe).contains(0)) return null;
    try {
      final text = utf8.decode(bytes);
      return text.startsWith('﻿') ? text.substring(1) : text;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<int?> size(RepoPath path) async => _content[path]?.length;

  /// FNV-1a over the bytes: stable, and equal for equal content, which is
  /// all a blob id has to be for tests.
  static String _blobId(Uint8List bytes) {
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

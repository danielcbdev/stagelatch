/// Syntactic facts, looked up by blob id before they are extracted
/// (docs/specs/dart-toolchain.md, section 6.1).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:stagelatch/src/application/ports/cache.dart';
import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:stagelatch/src/infrastructure/dart/facts_codec.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';

/// Answers `facts` from a [Cache] when it can and from [SyntacticFacts]
/// when it cannot.
///
/// A hit is indistinguishable from recomputation, and the blob is not read.
/// Any [Exception] from the cache and any entry that does not decode is a
/// miss: the facts are recomputed and written again, so the verdict never
/// depends on the cache.
final class CachedFacts {
  /// Creates the lookup. The key includes `extractor.testFunctions`,
  /// because the facts depend on that set (ADR-0017).
  new({required SyntacticFacts extractor, required this._cache})
    : _extractor = extractor,
      _functionsHash = sha256
          .convert(
            utf8.encode(([...extractor.testFunctions]..sort()).join('\n')),
          )
          .toString();

  static const String _namespace = 'facts-v$factsFormatVersion';

  final SyntacticFacts _extractor;
  final Cache _cache;
  final String _functionsHash;

  /// The facts of [path] in [files], or null when it is not a regular or
  /// executable file, or is not text. Nothing is stored for those.
  Future<DartFileFacts?> facts(SnapshotFiles files, RepoPath path) async {
    final entry = await files.entry(path);
    if (entry == null || !entry.mode.isFile) return null;
    final key = '${entry.blobId}-$_functionsHash';

    final stored = await _read(key);
    if (stored != null) {
      final facts = decodeFacts(stored, path);
      if (facts != null) return facts;
    }

    final text = await files.readText(path);
    if (text == null) return null;
    final facts = _extractor.extract(text, path);
    await _write(key, encodeFacts(facts));
    return facts;
  }

  Future<String?> _read(String key) async {
    try {
      return await _cache.read(_namespace, key);
    } on Exception {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _cache.write(_namespace, key, value);
    } on Exception {
      // The cache is an optimization; the facts are right without it.
    }
  }
}

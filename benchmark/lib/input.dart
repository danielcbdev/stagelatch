/// Builds a [ProbeInput] from the current state of the corpus.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/probe.dart';
import 'package:stagelatch_bench/proc.dart';
import 'package:stagelatch_bench/workspace.dart';

/// Reads the index of the corpus and returns the input a gate would build.
///
/// - Overlays: every path that differs between index and working tree
///   (`git diff --name-only`), with its index content. This is the rule of
///   ADR-0001 and `specs/dart-toolchain.md` section 4.
/// - Files to diagnose and to format: the staged `.dart` files
///   (index vs HEAD) inside the package.
Future<ProbeInput> buildProbeInput({
  required String sdkRoot,
  BenchWorkspace? workspace,
}) async {
  final ws = workspace ?? BenchWorkspace.find();
  final corpus = Corpus.load(ws);
  final repo = ws.corpusDir;
  final packageRoot = p.normalize(p.join(repo, corpus.packageDir));

  // -z: NUL-separated, safe for any path. --no-renames: both sides of a
  // rename are plain paths. No commit argument: index vs working tree.
  final diverging = _paths(
    await run('git', [
      'diff',
      '--name-only',
      '-z',
      '--no-renames',
    ], workingDirectory: repo),
  );
  // --cached HEAD: index vs HEAD, the changeset of a pre-commit run.
  // --diff-filter=d: deleted files have nothing to diagnose.
  final staged = _paths(
    await run('git', [
      'diff',
      '--cached',
      '--name-only',
      '-z',
      '--no-renames',
      '--diff-filter=d',
      'HEAD',
    ], workingDirectory: repo),
  );

  final blobs = await readIndexBlobs(repo, diverging);
  final overlays = <String, String>{
    for (final (i, path) in diverging.indexed) p.join(repo, path): blobs[i],
  };

  final dartFiles = [
    for (final path in staged)
      if (path.endsWith('.dart') && p.isWithin(packageRoot, p.join(repo, path)))
        p.join(repo, path),
  ]..sort();

  return ProbeInput(
    repoRoot: repo,
    packageRoot: packageRoot,
    sdkRoot: sdkRoot,
    overlays: overlays,
    files: dartFiles,
    toFormat: dartFiles,
  );
}

List<String> _paths(String nulSeparated) =>
    nulSeparated.split('\x00').where((s) => s.isNotEmpty).toList()..sort();

/// Reads [path] as the probe would: overlay first, then disk.
String readThroughOverlay(ProbeInput input, String path) =>
    input.overlays[path] ?? File(path).readAsStringSync();

/// Reads the index content of [paths] through one `git cat-file --batch`
/// process, as the real tool does (ADR-0001): one spawn, not one per file.
///
/// Results are in the order of [paths]. A path absent from the index
/// yields an empty string (the scenarios never delete files).
Future<List<String>> readIndexBlobs(String repo, List<String> paths) async {
  if (paths.isEmpty) return const [];
  final process = await Process.start('git', [
    'cat-file',
    '--batch',
  ], workingDirectory: repo);
  final reader = _ByteReader(process.stdout);
  try {
    final result = <String>[];
    for (final path in paths) {
      // ':<path>' names the blob of <path> in the index (stage 0).
      process.stdin.add(utf8.encode(':$path\n'));
      await process.stdin.flush();
      final header = utf8.decode(await reader.readLine());
      if (header.endsWith(' missing')) {
        result.add('');
        continue;
      }
      final size = int.parse(header.split(' ')[2]);
      final body = await reader.read(size);
      await reader.read(1); // The newline after each object.
      result.add(utf8.decode(body));
    }
    return result;
  } finally {
    await process.stdin.close();
    await reader.cancel();
    process.kill();
    await process.exitCode;
  }
}

/// Sequential reads over a byte stream.
final class _ByteReader {
  new(Stream<List<int>> stream) {
    _subscription = stream.listen((chunk) {
      _buffer.add(chunk);
      _wake();
    });
  }

  late final StreamSubscription<List<int>> _subscription;
  final _buffer = BytesBuilder(copy: false);
  Completer<void>? _waiting;

  void _wake() {
    final waiting = _waiting;
    _waiting = null;
    waiting?.complete();
  }

  Future<void> _waitFor(bool Function(Uint8List) ready) async {
    while (!ready(_buffer.toBytes())) {
      final waiting = _waiting = Completer<void>();
      await waiting.future;
    }
  }

  Future<Uint8List> readLine() async {
    await _waitFor((b) => b.contains(10));
    final bytes = _buffer.takeBytes();
    final end = bytes.indexOf(10);
    _buffer.add(bytes.sublist(end + 1));
    return bytes.sublist(0, end);
  }

  Future<Uint8List> read(int count) async {
    await _waitFor((b) => b.length >= count);
    final bytes = _buffer.takeBytes();
    _buffer.add(bytes.sublist(count));
    return bytes.sublist(0, count);
  }

  Future<void> cancel() => _subscription.cancel();
}

/// Measures directive extraction and the import graph on the corpus.
///
/// `dart run benchmark/bin/graph.dart parse|scan|compare`
///
/// `parse` and `scan` time one extractor in a fresh process over every
/// `.dart` file at the pinned commit, read by blob id through one
/// `git cat-file --batch`. `compare` runs both and lists the files where
/// they disagree, then times the transitive dependents of the widely
/// imported file of scenario s10.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/directives_parse.dart';
import 'package:stagelatch_bench/directives_scan.dart';
import 'package:stagelatch_bench/input.dart';
import 'package:stagelatch_bench/proc.dart';
import 'package:stagelatch_bench/workspace.dart';

/// The file of s10 that more than a hundred files import.
const _hub = 'lib/core/wallpaper/wallpaper_source.dart';

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'compare' : args.single;
  final ws = BenchWorkspace.find();
  final corpus = Corpus.load(ws);
  final repo = ws.corpusDir;

  final read = Stopwatch()..start();
  // -r: recurse into subtrees. -z: NUL-terminated records, safe for any
  // path. The pinned SHA, not HEAD or the index: the file set is fixed.
  final listing = await run('git', [
    'ls-tree',
    '-r',
    '-z',
    corpus.sha,
  ], workingDirectory: repo);
  final entries = [
    for (final record in listing.split('\x00'))
      if (record.endsWith('.dart'))
        (
          blob: record.split(' ')[2].split('\t').first,
          path: record.substring(record.indexOf('\t') + 1),
        ),
  ];
  final sources = await readBlobs(repo, [for (final e in entries) e.blob]);
  read.stop();
  stdout.writeln(
    'files: ${entries.length}, read through cat-file --batch: '
    '${read.elapsedMilliseconds} ms',
  );

  List<List<String>> extract(List<String> Function(String) extractor) {
    final watch = Stopwatch()..start();
    final result = [for (final s in sources) extractor(s)];
    stdout.writeln('${_name(extractor)}: ${watch.elapsedMilliseconds} ms');
    return result;
  }

  switch (mode) {
    case 'parse':
      extract(directivesByParser);
    case 'scan':
      extract(directivesByScanner);
    case 'compare':
      final parsed = extract(directivesByParser);
      final scanned = extract(directivesByScanner);
      var disagree = 0;
      for (var i = 0; i < entries.length; i++) {
        if (parsed[i].join('\n') != scanned[i].join('\n')) {
          disagree++;
          stdout.writeln(
            '  disagree: ${entries[i].path}\n'
            '    parse: ${parsed[i]}\n    scan:  ${scanned[i]}',
          );
        }
      }
      stdout.writeln('disagreeing files: $disagree');
      _dependents(ws, corpus, entries.map((e) => e.path).toList(), parsed);
    default:
      stderr.writeln('Usage: graph parse|scan|compare');
      exitCode = 64;
  }
}

String _name(List<String> Function(String) f) =>
    identical(f, directivesByParser) ? 'parseString' : 'scanner';

/// Builds the reverse import graph and times the transitive dependents of
/// [_hub], following `specs/dart-toolchain.md` section 3.
void _dependents(
  BenchWorkspace ws,
  Corpus corpus,
  List<String> paths,
  List<List<String>> uris,
) {
  final watch = Stopwatch()..start();
  // Package roots of this repository: every directory with a pubspec.yaml,
  // keyed by the package name it declares would need the pubspec; the
  // corpus's own name is enough here.
  final packageName =
      File(
            p.join(
              BenchWorkspace.find().corpusDir,
              corpus.packageDir,
              'pubspec.yaml',
            ),
          )
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('name:'))
          .substring(5)
          .trim();
  final prefix = 'package:$packageName/';
  final importers = <String, Set<String>>{};
  for (var i = 0; i < paths.length; i++) {
    final from = paths[i];
    for (final uri in uris[i]) {
      final String target;
      if (uri.startsWith(prefix)) {
        target = p.posix.normalize(
          p.posix.join(corpus.packageDir, 'lib', uri.substring(prefix.length)),
        );
      } else if (uri.contains(':')) {
        continue; // dart: and other packages are external.
      } else {
        target = p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
      }
      (importers[target] ??= {}).add(from);
    }
  }
  final built = watch.elapsedMicroseconds;
  final seen = <String>{_hub};
  final queue = [_hub];
  while (queue.isNotEmpty) {
    for (final next in importers[queue.removeLast()] ?? const <String>{}) {
      if (seen.add(next)) queue.add(next);
    }
  }
  final total = watch.elapsedMicroseconds;
  stdout.writeln(
    'graph: ${importers.length} imported files, built in '
    '${(built / 1000).toStringAsFixed(1)} ms; dependents of $_hub: '
    '${seen.length} files in ${((total - built) / 1000).toStringAsFixed(1)} ms',
  );
}

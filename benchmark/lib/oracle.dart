/// The parity oracle: what the SDK's own tools say about the snapshot.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/probe.dart';

/// Runs the corpus SDK's `dart analyze` and `dart format` on a copy of the
/// index, exported to a temporary directory, and maps the results back to
/// repository paths.
///
/// This is the definition of parity (ADR-0008): a probe passes when it
/// reports what these commands report on a working tree identical to the
/// snapshot.
Future<ProbeResult> runOracle(
  ProbeInput input, {
  required String scratchDir,
}) async {
  final tmp = (Directory(
    p.join(scratchDir, 'oracle'),
  )..createSync(recursive: true)).createTempSync('tree-');
  try {
    final repo = input.repoRoot;
    // write-tree: a tree object of the index exactly as staged.
    final tree = (await _run('git', ['write-tree'], repo)).stdout.trim();
    await _export(repo, tree, tmp.path);

    final relativePackage = p.relative(input.packageRoot, from: repo);
    final package = p.normalize(p.join(tmp.path, relativePackage));
    _copyPackageConfig(
      from: p.join(input.packageRoot, '.dart_tool', 'package_config.json'),
      to: p.join(package, '.dart_tool', 'package_config.json'),
      repoRoot: repo,
    );

    String toTmp(String path) => p.join(tmp.path, p.relative(path, from: repo));
    String toRepo(String path) =>
        p.join(repo, p.relative(path, from: tmp.path));

    final dart = p.join(input.sdkRoot, 'bin', 'dart');
    final cache = Directory(p.join(scratchDir, 'oracle-cache'))
      ..createSync(recursive: true);
    // --format=json: machine-readable diagnostics with offsets.
    // --cache: never the user's own analysis cache.
    // No --fatal flags: the exit code says "issues found", which is fine.
    final analyzed = await _run(
      dart,
      [
        '--suppress-analytics',
        'analyze',
        '--format=json',
        '--cache=${cache.path}',
        package,
      ],
      package,
      allowFailure: true,
    );
    final requested = {for (final f in input.files) toTmp(f)};
    final diagnostics = [
      for (final d in _diagnostics(analyzed.stdout))
        if (requested.contains(d.path))
          ProbeDiagnostic(
            path: toRepo(d.path),
            code: d.code,
            severity: d.severity,
            offset: d.offset,
            length: d.length,
            message: d.message,
          ),
    ];

    final formatted = <String, String>{};
    for (final file in input.toFormat) {
      // --output=json: one object per file with the formatted source,
      // without touching the file. Run from the package so that
      // analysis_options.yaml and package_config.json of the snapshot are
      // the ones found.
      final result = await _run(dart, [
        '--suppress-analytics',
        'format',
        '--output=json',
        toTmp(file),
      ], package);
      final json = jsonDecode(result.stdout.trim().split('\n').last);
      if (json case {'source': final String source}) {
        formatted[file] = source;
      } else {
        throw FormatException('Unexpected dart format output', result.stdout);
      }
    }

    return ProbeResult(
      diagnostics: diagnostics,
      formatted: formatted,
      phases: const {},
    );
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

/// Lists differences between [expected] (the oracle) and [actual], one line
/// each; empty when the probe matches.
///
/// Diagnostics are compared as the set of `(path, code, severity, offset,
/// length)`; formatted text byte for byte.
List<String> diffResults(ProbeResult expected, ProbeResult actual) {
  String key(ProbeDiagnostic d) =>
      '${d.path}|${d.code}|${d.severity}|${d.offset}|${d.length}';
  final want = {for (final d in expected.diagnostics) key(d): d};
  final got = {for (final d in actual.diagnostics) key(d): d};
  final lines = <String>[
    for (final k in want.keys)
      if (!got.containsKey(k)) 'missing  ${_describe(want[k]!)}',
    for (final k in got.keys)
      if (!want.containsKey(k)) 'extra    ${_describe(got[k]!)}',
  ];
  final paths = {...expected.formatted.keys, ...actual.formatted.keys}.toList()
    ..sort();
  for (final path in paths) {
    final a = expected.formatted[path];
    final b = actual.formatted[path];
    if (a != b) {
      lines.add('format   $path: ${_firstDifference(a, b)}');
    }
  }
  return lines..sort();
}

String _describe(ProbeDiagnostic d) =>
    '${d.severity} ${d.code} ${d.path}@${d.offset}+${d.length}';

String _firstDifference(String? a, String? b) {
  if (a == null || b == null) return 'missing on one side';
  final la = const LineSplitter().convert(a);
  final lb = const LineSplitter().convert(b);
  for (var i = 0; i < la.length && i < lb.length; i++) {
    if (la[i] != lb[i]) {
      return 'line ${i + 1}: expected "${la[i]}", got "${lb[i]}"';
    }
  }
  if (la.length != lb.length) {
    return 'line count ${la.length} vs ${lb.length}';
  }
  return 'line endings or trailing newline differ';
}

Iterable<ProbeDiagnostic> _diagnostics(String json) sync* {
  final decoded = jsonDecode(json);
  if (decoded case {'diagnostics': final List<Object?> list}) {
    for (final d in list) {
      if (d case {
        'code': final String code,
        'severity': final String severity,
        'problemMessage': final String message,
        'location': {
          'file': final String file,
          'range': {
            'start': {'offset': final int start},
            'end': {'offset': final int end},
          },
        },
      }) {
        yield ProbeDiagnostic(
          path: file,
          code: code,
          severity: severity.toLowerCase(),
          offset: start,
          length: end - start,
          message: message,
        );
      }
    }
  }
}

/// Extracts [tree] of [repo] into [dir] with `git archive | tar -x`.
Future<void> _export(String repo, String tree, String dir) async {
  final archive = await Process.start('git', [
    'archive',
    '--format=tar',
    tree,
  ], workingDirectory: repo);
  final tar = await Process.start('tar', ['-x', '-f', '-', '-C', dir]);
  final errors = archive.stderr.transform(utf8.decoder).join();
  await archive.stdout.pipe(tar.stdin);
  final codes = await Future.wait([archive.exitCode, tar.exitCode]);
  if (codes.any((c) => c != 0)) {
    throw ProcessException('git archive | tar', [tree], await errors, codes[0]);
  }
}

/// Copies the package config so the exported tree resolves the same
/// packages as the corpus.
///
/// Roots outside the repository (pub cache, Flutter SDK) become absolute.
/// Roots inside it (the package itself, path dependencies under
/// `packages/`) stay relative, so they resolve to the exported copy and
/// never to the working tree.
void _copyPackageConfig({
  required String from,
  required String to,
  required String repoRoot,
}) {
  final json = jsonDecode(File(from).readAsStringSync());
  final base = Uri.directory(p.dirname(from));
  if (json case {'packages': final List<Object?> packages}) {
    for (final entry in packages) {
      if (entry case {'rootUri': final String rootUri}
          when entry is Map<String, Object?>) {
        final absolute = base.resolve(rootUri).toFilePath();
        if (!p.isWithin(repoRoot, absolute) && !p.equals(repoRoot, absolute)) {
          entry['rootUri'] = Uri.directory(absolute).toString();
        }
      }
    }
  }
  File(to)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(json));
}

Future<({String stdout, String stderr})> _run(
  String executable,
  List<String> args,
  String dir, {
  bool allowFailure = false,
}) async {
  final result = await Process.run(executable, args, workingDirectory: dir);
  final out = result.stdout as String;
  final err = result.stderr as String;
  if (!allowFailure && result.exitCode != 0) {
    throw ProcessException(executable, args, err, result.exitCode);
  }
  return (stdout: out, stderr: err);
}

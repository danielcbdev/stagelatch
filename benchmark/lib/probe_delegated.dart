/// Candidate B: the resolved SDK's analysis server, in a child process.
library;

import 'dart:io';

import 'package:stagelatch_bench/input.dart';
import 'package:stagelatch_bench/probe.dart';
import 'package:stagelatch_bench/server_client.dart';

/// When to ask for diagnostics after installing the overlays.
enum WaitStrategy {
  /// Send `analysis.getErrors` right away. The protocol says the response
  /// is delayed until the file's errors are up to date.
  immediate,

  /// Wait until `server.status` reports that analysis finished.
  idle,
}

/// What `analysis.setAnalysisRoots` receives.
enum RootsMode {
  /// The package directory: the server analyzes every file in it.
  package,

  /// Only the files to diagnose: the server analyzes them and what they
  /// import, nothing else.
  files,
}

/// Diagnoses and formats through `dart language-server --protocol=analyzer`.
final class DelegatedProbe implements Probe {
  /// Creates the probe; [cacheDir] is passed to the server's `--cache`.
  const new({
    required this.cacheDir,
    this.wait = WaitStrategy.immediate,
    this.priority = true,
    this.roots = RootsMode.package,
  });

  /// Cache directory handed to the server.
  final String cacheDir;

  /// See [WaitStrategy].
  final WaitStrategy wait;

  /// Whether the requested files are made priority files, so the server
  /// analyzes them before the rest of the package.
  final bool priority;

  /// See [RootsMode].
  final RootsMode roots;

  @override
  String get name => [
    'delegated',
    if (roots == RootsMode.files) 'files',
    if (wait == WaitStrategy.idle) 'idle',
  ].join('-');

  @override
  Future<ProbeResult> run(ProbeInput input) async {
    final phases = <String, Duration>{};
    final clock = Stopwatch()..start();
    Duration lap() {
      final elapsed = clock.elapsed;
      clock.reset();
      return elapsed;
    }

    Directory(cacheDir).createSync(recursive: true);
    final server = await ServerClient.start(input.sdkRoot, cacheDir: cacheDir);
    try {
      // Subscribe before setting roots, or the status changes are lost.
      final idle = _analysisFinished(server.notifications);
      if (wait == WaitStrategy.idle) {
        // server.status is only sent to clients subscribed to STATUS.
        await server.request('server.setSubscriptions', {
          'subscriptions': ['STATUS'],
        });
      }
      phases['start'] = lap();

      // Overlays first, roots second: the server must never analyze the
      // working-tree content of an overlaid file.
      await server.request('analysis.updateContent', {
        'files': {
          for (final MapEntry(key: path, value: content)
              in input.overlays.entries)
            path: {'type': 'add', 'content': content},
        },
      });
      await server.request('analysis.setAnalysisRoots', {
        'included': switch (roots) {
          RootsMode.package => [input.packageRoot],
          RootsMode.files => input.files,
        },
        'excluded': <String>[],
      });
      if (priority) {
        await server.request('analysis.setPriorityFiles', {
          'files': input.files,
        });
      }
      phases['overlay'] = lap();

      if (wait == WaitStrategy.idle) await idle;
      final diagnostics = <ProbeDiagnostic>[];
      final responses = await Future.wait([
        for (final path in input.files)
          server.request('analysis.getErrors', {'file': path}),
      ]);
      for (final (i, response) in responses.indexed) {
        diagnostics.addAll(_diagnostics(input.files[i], response));
      }
      phases['diagnose'] = lap();

      final formatted = <String, String>{};
      for (final path in input.toFormat) {
        final source = readThroughOverlay(input, path);
        // Selection 0/0: we want the whole file and no cursor mapping. No
        // lineLength: the server reads `formatter: page_width` itself.
        final response = await server.request('edit.format', {
          'file': path,
          'selectionOffset': 0,
          'selectionLength': 0,
        });
        formatted[path] = _applyEdits(source, response);
      }
      phases['format'] = lap();

      return ProbeResult(
        diagnostics: diagnostics,
        formatted: formatted,
        phases: phases,
      );
    } finally {
      await server.close();
    }
  }

  /// Completes when `server.status` reports analysis finished after having
  /// reported it started, so an idle status sent before the roots are set
  /// does not count.
  static Future<void> _analysisFinished(
    Stream<Map<String, Object?>> notifications,
  ) async {
    var started = false;
    await for (final n in notifications) {
      if (n case {
        'event': 'server.status',
        'params': {'analysis': {'isAnalyzing': final bool analyzing}},
      }) {
        if (analyzing) {
          started = true;
        } else if (started) {
          return;
        }
      }
    }
  }

  static Iterable<ProbeDiagnostic> _diagnostics(
    String path,
    Map<String, Object?> response,
  ) sync* {
    final errors = response['errors'];
    if (errors is! List<Object?>) return;
    for (final error in errors) {
      if (error
          case {
            'severity': final String severity,
            'code': final String code,
            'message': final String message,
            'location': {
              'file': final String file,
              'offset': final int offset,
              'length': final int length,
            },
          }
          when file == path) {
        yield ProbeDiagnostic(
          path: path,
          code: code,
          severity: severity.toLowerCase(),
          offset: offset,
          length: length,
          message: message,
        );
      }
    }
  }

  static String _applyEdits(String source, Map<String, Object?> response) {
    final edits = [
      if (response['edits'] case final List<Object?> list)
        for (final edit in list)
          if (edit case {
            'offset': final int offset,
            'length': final int length,
            'replacement': final String replacement,
          })
            (offset: offset, length: length, replacement: replacement),
    ]..sort((a, b) => b.offset.compareTo(a.offset));
    // Applied from the end so earlier offsets stay valid.
    var text = source;
    for (final edit in edits) {
      text = text.replaceRange(
        edit.offset,
        edit.offset + edit.length,
        edit.replacement,
      );
    }
    return text;
  }
}

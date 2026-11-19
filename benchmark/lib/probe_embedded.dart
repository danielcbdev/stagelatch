/// Candidate A: `package:analyzer` and `package:dart_style` in-process.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/source/error_processor.dart';
// The public AnalysisContextCollection takes no byte store; the
// implementation class is the only way to point the analyzer's cache at a
// directory of our choosing (cold runs need an empty one).
// ignore: implementation_imports, the spike measures the cache explicitly.
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
// ignore: implementation_imports, same reason as above.
import 'package:analyzer/src/dart/analysis/byte_store.dart';
// ignore: implementation_imports, same reason as above.
import 'package:analyzer/src/dart/analysis/file_byte_store.dart';
import 'package:dart_style/dart_style.dart';
import 'package:stagelatch_bench/format_options.dart';
import 'package:stagelatch_bench/input.dart';
import 'package:stagelatch_bench/probe.dart';

/// Diagnoses with an in-process analyzer over an overlay file system and
/// formats with the embedded `dart_style`.
final class EmbeddedProbe implements Probe {
  /// Creates the probe. [cacheDir] holds the analyzer's byte store; null
  /// keeps it in memory, so every run is cold.
  const new({this.cacheDir});

  /// Directory of the analyzer's on-disk cache, or null for memory only.
  final String? cacheDir;

  @override
  String get name => 'embedded';

  @override
  Future<ProbeResult> run(ProbeInput input) async {
    final phases = <String, Duration>{};
    final clock = Stopwatch()..start();
    Duration lap() {
      final elapsed = clock.elapsed;
      clock.reset();
      return elapsed;
    }

    // Overlays sit on top of the physical file system: reads of an
    // overlaid path return the snapshot content, everything else (the SDK,
    // the pub cache, unchanged files) comes from disk.
    final provider = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
    for (final MapEntry(key: path, value: content) in input.overlays.entries) {
      // modificationStamp 0: constant, so cache keys depend on content only.
      provider.setOverlay(path, content: content, modificationStamp: 0);
    }
    phases['overlay'] = lap();

    final dir = cacheDir;
    // FileByteStore does not create its directory, and a failed write is
    // silent: every run would then be cold.
    if (dir != null) Directory(dir).createSync(recursive: true);
    final collection = AnalysisContextCollectionImpl(
      includedPaths: [input.packageRoot],
      resourceProvider: provider,
      // The SDK the project uses, not the one the tool runs on (ADR-0008).
      sdkPath: input.sdkRoot,
      byteStore: dir == null
          ? MemoryByteStore()
          : MemoryCachingByteStore(FileByteStore(dir), 64 * 1024 * 1024),
    );
    phases['start'] = lap();

    try {
      final diagnostics = <ProbeDiagnostic>[];
      for (final path in input.files) {
        final context = collection.contextFor(path);
        // getErrors resolves the library and returns the diagnostics of one
        // file, with `// ignore:` comments already applied.
        final result = await context.currentSession.getErrors(path);
        if (result is! ErrorsResult) {
          throw StateError('No diagnostics for $path: $result');
        }
        final options = context.getAnalysisOptionsForFile(
          provider.getFile(path),
        );
        for (final diagnostic in result.diagnostics) {
          // analysis_options `errors:` entries: a processor with no severity
          // drops the diagnostic, otherwise it replaces the severity. This
          // is what `dart analyze` applies before printing.
          final processor = ErrorProcessor.getProcessor(options, diagnostic);
          if (processor != null && processor.severity == null) continue;
          // Diagnostic.severity is a different, coarser enum; the code's
          // DiagnosticSeverity is what an ErrorProcessor replaces.
          final severity =
              processor?.severity ?? diagnostic.diagnosticCode.severity;
          if (diagnostic.diagnosticCode.type == DiagnosticType.TODO) continue;
          diagnostics.add(
            ProbeDiagnostic(
              path: path,
              code: diagnostic.diagnosticCode.lowerCaseName,
              severity: severity.displayName,
              offset: diagnostic.offset,
              length: diagnostic.length,
              message: diagnostic.message,
            ),
          );
        }
      }
      phases['diagnose'] = lap();

      final formatted = <String, String>{};
      for (final path in input.toFormat) {
        final options = FormatOptions.resolve(input, path);
        final formatter = DartFormatter(
          languageVersion: options.languageVersion,
          pageWidth: options.pageWidth,
          trailingCommas: options.preserveTrailingCommas
              ? TrailingCommas.preserve
              : TrailingCommas.automate,
        );
        formatted[path] = formatter.format(
          readThroughOverlay(input, path),
          uri: path,
        );
      }
      phases['format'] = lap();

      return ProbeResult(
        diagnostics: diagnostics,
        formatted: formatted,
        phases: phases,
      );
    } finally {
      await collection.dispose();
    }
  }
}

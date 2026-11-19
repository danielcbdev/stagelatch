/// The interface both candidate mechanisms implement (plan 00, Task 2).
library;

/// What a probe is asked to do: diagnose and format files of one package,
/// seeing [overlays] instead of the working tree for the paths they name.
final class ProbeInput {
  /// Creates an input. Collections are stored as unmodifiable copies.
  new({
    required this.repoRoot,
    required this.packageRoot,
    required this.sdkRoot,
    required Map<String, String> overlays,
    required List<String> files,
    required List<String> toFormat,
  }) : overlays = Map.unmodifiable(overlays),
       files = List.unmodifiable(files),
       toFormat = List.unmodifiable(toFormat);

  /// Absolute path of the corpus repository.
  final String repoRoot;

  /// Absolute path of the analyzed package (the directory of its pubspec).
  final String packageRoot;

  /// Absolute path of the Dart SDK (not the Flutter SDK).
  final String sdkRoot;

  /// Absolute path to snapshot content.
  final Map<String, String> overlays;

  /// Absolute paths whose diagnostics are reported.
  final List<String> files;

  /// Absolute paths to format; content comes from [overlays] when present.
  final List<String> toFormat;

  /// This input without overlays: the probe then sees the working tree.
  ProbeInput withoutOverlays() => ProbeInput(
    repoRoot: repoRoot,
    packageRoot: packageRoot,
    sdkRoot: sdkRoot,
    overlays: const {},
    files: files,
    toFormat: toFormat,
  );
}

/// One diagnostic, in the shape `dart analyze --format=json` reports it.
final class ProbeDiagnostic implements Comparable<ProbeDiagnostic> {
  /// Creates a diagnostic.
  const new({
    required this.path,
    required this.code,
    required this.severity,
    required this.offset,
    required this.length,
    required this.message,
  });

  /// Absolute path of the file the diagnostic is in.
  final String path;

  /// Lower-case diagnostic code, for example `unused_local_variable`.
  final String code;

  /// `error`, `warning` or `info`.
  final String severity;

  /// Zero-based offset of the range, in UTF-16 code units.
  final int offset;

  /// Length of the range, in UTF-16 code units.
  final int length;

  /// The problem message.
  final String message;

  /// Orders by path, offset, then code: the order of [ProbeResult].
  @override
  int compareTo(ProbeDiagnostic other) {
    final byPath = path.compareTo(other.path);
    if (byPath != 0) return byPath;
    final byOffset = offset.compareTo(other.offset);
    if (byOffset != 0) return byOffset;
    return code.compareTo(other.code);
  }

  /// JSON form, for reports.
  Map<String, Object> toJson() => {
    'path': path,
    'code': code,
    'severity': severity,
    'offset': offset,
    'length': length,
    'message': message,
  };
}

/// What a probe produced and how long each phase took.
final class ProbeResult {
  /// Creates a result; [diagnostics] are sorted here.
  new({
    required List<ProbeDiagnostic> diagnostics,
    required Map<String, String> formatted,
    required Map<String, Duration> phases,
  }) : diagnostics = List.unmodifiable([...diagnostics]..sort()),
       formatted = Map.unmodifiable(formatted),
       phases = Map.unmodifiable(phases);

  /// Sorted by path, offset, code.
  final List<ProbeDiagnostic> diagnostics;

  /// Absolute path to formatted text.
  final Map<String, String> formatted;

  /// Phase name (`start`, `overlay`, `diagnose`, `format`) to duration.
  final Map<String, Duration> phases;
}

/// A mechanism that diagnoses and formats a snapshot.
abstract interface class Probe {
  /// Short name used on the command line and in the report.
  String get name;

  /// Runs once over [input], starting and stopping everything it needs.
  Future<ProbeResult> run(ProbeInput input);
}

import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';

/// A [DartToolchain] with canned answers that records every call.
final class FakeDartToolchain implements DartToolchain {
  /// Creates a toolchain. [diagnostics] answer `diagnose` (only the
  /// requested files are returned); [formatted] answers `format` by path,
  /// and a path that is not there is returned unchanged. Facts come from
  /// the real directive scanner.
  new({
    this.diagnostics = const [],
    this.formatted = const {},
    this.unparseable = const {},
  });

  /// Every diagnostic this toolchain knows, for any file.
  final List<DartDiagnostic> diagnostics;

  /// What `format` returns, by repository path.
  final Map<String, String> formatted;

  /// Paths whose source does not parse.
  final Set<String> unparseable;

  /// The file sets passed to `diagnose`, in call order.
  final List<Set<RepoPath>> diagnoseCalls = [];

  /// The paths passed to `format`, in call order.
  final List<RepoPath> formatCalls = [];

  /// The paths passed to `facts`, in call order.
  final List<RepoPath> factsCalls = [];

  /// Whether [close] was called.
  bool closed = false;

  @override
  Future<List<DartDiagnostic>> diagnose(Set<RepoPath> files) async {
    diagnoseCalls.add(files);
    return [
      for (final diagnostic in diagnostics)
        if (files.contains(diagnostic.location.path)) diagnostic,
    ];
  }

  @override
  Future<FormatOutcome> format(RepoPath path, String source) async {
    formatCalls.add(path);
    if (unparseable.contains(path.value)) return const Unparseable();
    return Formatted(formatted[path.value] ?? source);
  }

  @override
  Future<DartFileFacts?> facts(SnapshotFiles files, RepoPath path) async {
    factsCalls.add(path);
    final text = await files.readText(path);
    return text == null ? null : const SyntacticFacts().extract(text, path);
  }

  @override
  Future<void> close() async => closed = true;
}

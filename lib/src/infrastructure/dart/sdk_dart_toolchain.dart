/// The Dart toolchain of ADR-0008: the project's resolved SDK does the work,
/// one shot per run (docs/specs/dart-toolchain.md, section 8).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/dart_toolchain_factory.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/snapshot.dart';
import 'package:stagelatch/src/infrastructure/dart/analysis_server_client.dart';
import 'package:stagelatch/src/infrastructure/dart/materialized_snapshot.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';

/// Creates [SdkDartToolchain]s.
final class SdkDartToolchainFactory implements DartToolchainFactory {
  /// Creates the factory.
  const new();

  @override
  DartToolchain create({
    required ResolvedSdk sdk,
    required String repoRoot,
    required SnapshotFiles snapshot,
    required PackageMap packages,
  }) => SdkDartToolchain(
    sdk: sdk,
    repoRoot: repoRoot,
    snapshot: snapshot,
    packages: packages,
  );
}

/// Diagnostics from the resolved SDK's analysis server over a materialized
/// snapshot; formatting from its `dart format`; facts from the directive
/// scanner. Nothing starts until a request needs it.
final class SdkDartToolchain implements DartToolchain {
  /// Creates the toolchain for `snapshot`.
  new({
    required this._sdk,
    required this._repoRoot,
    required this._snapshot,
    required this._packages,
  });

  final ResolvedSdk _sdk;
  final String _repoRoot;
  final SnapshotFiles _snapshot;
  final PackageMap _packages;

  Future<MaterializedSnapshot>? _full;
  Future<MaterializedSnapshot>? _settings;
  Future<AnalysisServerClient>? _server;

  @override
  Future<List<DartDiagnostic>> diagnose(Set<RepoPath> files) async {
    final requested = [...files]..sort();
    final roots = <RepoPath?>{};
    final analyzed = <RepoPath>[];
    for (final file in requested) {
      final package = _packages.packageOf(file);
      // Files outside every package are not Dart rules' business
      // (docs/specs/dart-toolchain.md, section 2).
      if (package == null) continue;
      roots.add(package.root);
      analyzed.add(file);
    }
    if (analyzed.isEmpty) return const [];
    roots.forEach(_requirePackageConfig);

    final full = await (_full ??= MaterializedSnapshot.write(
      snapshot: _snapshot,
      repoRoot: _repoRoot,
      packages: _packages.packages,
    ));
    final server = await (_server ??= AnalysisServerClient.start(
      _sdk.dartExecutable,
    ));
    // The roots of the packages that own the requested files; the server
    // analyzes everything under them, as `dart analyze` would.
    await server.request('analysis.setAnalysisRoots', {
      'included': [
        for (final root in roots)
          if (root == null) full.root else full.pathOf(root),
      ],
      'excluded': const <String>[],
    });
    // The requested files first: without priority files the server works
    // through the whole root in its own order, and getErrors waits for it.
    // The spike's measured probe set them too (benchmark/lib/
    // probe_delegated.dart).
    await server.request('analysis.setPriorityFiles', {
      'files': [for (final file in analyzed) full.pathOf(file)],
    });

    final diagnostics = <DartDiagnostic>[];
    for (final file in analyzed) {
      if (await _snapshot.entry(file) == null) continue;
      // getErrors answers once the file has been analyzed.
      final response = await server.request('analysis.getErrors', {
        'file': full.pathOf(file),
      });
      diagnostics.addAll(_diagnostics(response, file, full));
    }
    diagnostics.sort(_compare);
    return diagnostics;
  }

  void _requirePackageConfig(RepoPath? root) {
    final segments = [...?root?.value.split('/')];
    final config = File(
      p.joinAll([_repoRoot, ...segments, '.dart_tool', 'package_config.json']),
    );
    if (!config.existsSync()) {
      final relative = [...segments, '.dart_tool', 'package_config.json'];
      throw UsageException('Missing ${relative.join('/')}. Run: dart pub get');
    }
  }

  Iterable<DartDiagnostic> _diagnostics(
    Map<String, Object?> response,
    RepoPath file,
    MaterializedSnapshot full,
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
              'file': final String path,
              'startLine': final int startLine,
              'startColumn': final int startColumn,
              'endLine': final int endLine,
              'endColumn': final int endColumn,
            },
          }
          when full.repoPathOf(path) == file && !_isQuietTodo(error)) {
        final correction = (error as Map<String, Object?>)['correction'];
        yield DartDiagnostic(
          location: Location(
            file,
            Position(startLine, startColumn),
            Position(endLine, endColumn),
          ),
          code: code,
          severity: switch (severity) {
            'ERROR' => DiagnosticSeverity.error,
            'WARNING' => DiagnosticSeverity.warning,
            _ => DiagnosticSeverity.info,
          },
          message: _repoPaths(message, full),
          correction: correction is String
              ? _repoPaths(correction, full)
              : null,
        );
      }
    }
  }

  /// Whether [error] is a to-do comment at its default severity. The server
  /// reports those for editors; `dart analyze` drops them, and reports one
  /// only when `analysis_options.yaml` raises its severity (measured).
  static bool _isQuietTodo(Map<Object?, Object?> error) =>
      error['type'] == 'TODO' && error['severity'] == 'INFO';

  /// [text] with the materialized directory replaced by the repository
  /// root, so it reads as `dart analyze` in the working tree would print it.
  String _repoPaths(String text, MaterializedSnapshot full) =>
      text.replaceAll(full.root, _repoRoot);

  static int _compare(DartDiagnostic a, DartDiagnostic b) {
    final byPath = a.location.path.compareTo(b.location.path);
    if (byPath != 0) return byPath;
    final byStart = a.location.start.compareTo(b.location.start);
    if (byStart != 0) return byStart;
    return a.code.compareTo(b.code);
  }

  @override
  Future<FormatOutcome> format(RepoPath path, String source) async {
    // The settings come from the snapshot: page_width, trailing_commas and
    // the language version are found from the --stdin-name path, inside a
    // directory that holds only the snapshot's settings files.
    final settings = await (_settings ??= MaterializedSnapshot.write(
      snapshot: _snapshot,
      repoRoot: _repoRoot,
      packages: _packages.packages,
      settingsOnly: true,
    ));
    // dart format looks up the package config from the directory of the
    // --stdin-name path and silently falls back to the newest language
    // version when that directory does not exist (measured), so it is
    // created first.
    final stdinName = settings.pathOf(path);
    await Directory(p.dirname(stdinName)).create(recursive: true);
    final Process process;
    try {
      process = await Process.start(_sdk.dartExecutable, [
        '--suppress-analytics',
        'format',
        // --output=show: print the result instead of writing a file.
        '--output=show',
        // The source comes on stdin; this name only locates its settings.
        '--stdin-name=$stdinName',
      ]);
    } on ProcessException catch (error) {
      throw InternalException(
        'Cannot start dart format: ${error.message}',
        where: 'dart',
      );
    }
    final stdout = process.stdout.fold(
      BytesBuilder(copy: false),
      (builder, chunk) => builder..add(chunk),
    );
    final stderr = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    try {
      process.stdin.add(utf8.encode(source));
      await process.stdin.close();
    } on IOException {
      // dart format exited before reading; its exit code says why.
    }
    final exitCode = await process.exitCode;
    final output = (await stdout).takeBytes();
    final message = await stderr;
    return switch (exitCode) {
      0 => Formatted(utf8.decode(output)),
      // 65: the source does not parse; `analyze` reports why.
      65 => const Unparseable(),
      _ => throw InternalException(
        'dart format exited with $exitCode: ${message.trim()}',
        where: 'dart',
      ),
    };
  }

  @override
  Future<DartFileFacts?> facts(SnapshotFiles files, RepoPath path) async {
    final text = await files.readText(path);
    if (text == null) return null;
    return const SyntacticFacts().extract(text, path);
  }

  @override
  Future<void> close() async {
    final server = _server;
    final full = _full;
    final settings = _settings;
    _server = null;
    _full = null;
    _settings = null;
    try {
      if (server != null) await (await server).close();
    } finally {
      for (final directory in [full, settings].nonNulls) {
        await (await directory).delete();
      }
    }
  }
}

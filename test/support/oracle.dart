/// What the SDK's own `dart analyze` and `dart format` say about a package
/// on disk: the reference the Dart toolchain must equal (ADR-0008).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:test/test.dart';

/// One diagnostic in a form both sides can be compared in.
typedef OracleDiagnostic = ({
  String path,
  String code,
  String severity,
  int startLine,
  int startColumn,
  int endLine,
  int endColumn,
  String message,
});

/// The SDK's verdict on a package.
final class OracleResult {
  /// Creates a result.
  const new({required this.diagnostics, required this.formatted});

  /// Every diagnostic of `dart analyze`, paths relative to the package,
  /// sorted by path, position and code.
  final List<OracleDiagnostic> diagnostics;

  /// What `dart format` would write, by package-relative path.
  final Map<String, String> formatted;
}

/// Runs `dart analyze --format=json` on [packageDir] and `dart format
/// --output=json` on each of [format] (package-relative paths).
Future<OracleResult> runOracle(
  String packageDir, {
  List<String> format = const [],
}) async {
  final analyzed = await Process.run('dart', [
    '--suppress-analytics',
    'analyze',
    '--format=json',
    packageDir,
  ]);
  final output = (analyzed.stdout as String).trim();
  final start = output.indexOf('{');
  final json = start < 0
      ? const <String, Object?>{}
      : jsonDecode(output.substring(start)) as Map<String, Object?>;
  final diagnostics = <OracleDiagnostic>[
    for (final d in (json['diagnostics'] as List<Object?>?) ?? const [])
      if (d case {
        'code': final String code,
        'severity': final String severity,
        'problemMessage': final String message,
        'location': {
          'file': final String file,
          'range': {
            'start': {
              'line': final int startLine,
              'column': final int startColumn,
            },
            'end': {'line': final int endLine, 'column': final int endColumn},
          },
        },
      })
        (
          path: p.relative(file, from: packageDir).replaceAll(r'\', '/'),
          code: code,
          severity: severity.toLowerCase(),
          startLine: startLine,
          startColumn: startColumn,
          endLine: endLine,
          endColumn: endColumn,
          message: message,
        ),
  ]..sort(_compare);

  final formatted = <String, String>{};
  for (final path in format) {
    final result = await Process.run('dart', [
      '--suppress-analytics',
      'format',
      '--output=json',
      p.join(packageDir, path),
    ], workingDirectory: packageDir);
    final line = (result.stdout as String).trim().split('\n').last;
    final decoded = jsonDecode(line) as Map<String, Object?>;
    formatted[path] = decoded['source']! as String;
  }
  return OracleResult(diagnostics: diagnostics, formatted: formatted);
}

/// [diagnostics] in the oracle's comparable form.
List<OracleDiagnostic> comparable(List<DartDiagnostic> diagnostics) => [
  for (final d in diagnostics)
    (
      path: d.location.path.value,
      code: d.code,
      severity: d.severity.name,
      startLine: d.location.start.line,
      startColumn: d.location.start.column,
      endLine: d.location.end.line,
      endColumn: d.location.end.column,
      message: d.message,
    ),
]..sort(_compare);

/// Matches a toolchain result that equals [oracle]'s diagnostics.
Matcher equalsOracle(OracleResult oracle) => isA<List<DartDiagnostic>>().having(
  comparable,
  'diagnostics in comparable form',
  orderedEquals(oracle.diagnostics),
);

int _compare(OracleDiagnostic a, OracleDiagnostic b) {
  final byPath = a.path.compareTo(b.path);
  if (byPath != 0) return byPath;
  final byLine = a.startLine.compareTo(b.startLine);
  if (byLine != 0) return byLine;
  final byColumn = a.startColumn.compareTo(b.startColumn);
  if (byColumn != 0) return byColumn;
  return a.code.compareTo(b.code);
}

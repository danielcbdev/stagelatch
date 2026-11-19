/// The parameters of the `analyze` check (docs/specs/config.md, section 3).
library;

import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';

/// Which files `analyze` looks at.
enum AnalyzeScope {
  /// Only the changed Dart files.
  changed,

  /// The changed Dart files and everything that imports them.
  affected,

  /// Every Dart file of each package that has a changed file.
  all,
}

/// Parameters of the `analyze` check.
final class AnalyzeSettings {
  /// Creates the settings.
  const new({
    this.scope = AnalyzeScope.affected,
    this.failOn = const {DiagnosticSeverity.error, DiagnosticSeverity.warning},
  });

  /// Which files are analyzed.
  final AnalyzeScope scope;

  /// The analyzer severities that block.
  final Set<DiagnosticSeverity> failOn;
}

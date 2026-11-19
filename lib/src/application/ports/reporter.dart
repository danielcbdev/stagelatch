/// The port through which results reach the user.
library;

import 'package:stagelatch/src/application/pipeline/run_report.dart';

/// Presents the outcome of one invocation: as terminal text, JSON, or
/// annotations for a CI system.
abstract interface class Reporter {
  /// Reports every run of one invocation: one for pre-commit and ci, one
  /// per pushed branch for pre-push, none when there was nothing to judge.
  void report(List<RunReport> runs);
}

/// How the pipeline obtains a test runner (ADR-0018,
/// docs/specs/dart-toolchain.md, section 6).
library;

import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/domain/dart/test_runner.dart';

/// Creates test runners bound to one SDK and one repository.
abstract interface class TestRunnerFactory {
  /// A runner that starts the tests of [sdk] in the working tree at
  /// [repoRoot].
  ///
  /// Creating starts no process: that happens on the first `run`.
  TestRunner create({required ResolvedSdk sdk, required String repoRoot});
}

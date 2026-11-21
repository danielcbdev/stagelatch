/// The port through which `tests/affected` runs a package's tests
/// (ADR-0018, docs/specs/dart-toolchain.md, section 6).
library;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// One test that failed or threw.
///
/// Named `FailedTest` and not `TestFailure` because `package:test` exports a
/// `TestFailure` of its own.
@immutable
final class FailedTest {
  /// Creates a failed test.
  const new({
    required this.file,
    required this.line,
    required this.column,
    required this.name,
  });

  /// The test file that declares the test, or the first file of the run when
  /// the test tool gave no location inside the repository.
  final RepoPath file;

  /// The 1-based line of the declaration, `1` when unknown.
  final int line;

  /// The 1-based column of the declaration, `1` when unknown.
  final int column;

  /// The full name: the names of the enclosing groups and the test.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is FailedTest &&
      other.file == file &&
      other.line == line &&
      other.column == column &&
      other.name == name;

  @override
  int get hashCode => Object.hash(file, line, column, name);

  @override
  String toString() => 'FailedTest($name at $file:$line:$column)';
}

/// What running some test files produced.
@immutable
final class TestRunResult {
  /// Creates a result.
  const new({this.failures = const [], this.startupError});

  /// The results of consecutive runs as one: every failure in order, and the
  /// first startup error.
  factory merge(Iterable<TestRunResult> results) {
    final failures = <FailedTest>[];
    String? startupError;
    for (final result in results) {
      failures.addAll(result.failures);
      startupError ??= result.startupError;
    }
    return TestRunResult(failures: failures, startupError: startupError);
  }

  /// The failures of every merged run, in the order they were found.
  final List<FailedTest> failures;

  /// Why the tests could not run, or null when they did.
  ///
  /// A result with a startup error is never a pass, whatever [failures]
  /// holds: the tool could not load or start at least one file.
  final String? startupError;

  @override
  bool operator ==(Object other) =>
      other is TestRunResult &&
      other.startupError == startupError &&
      const ListEquality<FailedTest>().equals(other.failures, failures);

  @override
  int get hashCode => Object.hash(
    startupError,
    const ListEquality<FailedTest>().hash(failures),
  );

  @override
  String toString() =>
      'TestRunResult(${failures.length} failures, startupError: $startupError)';
}

/// Runs test files of one package.
abstract interface class TestRunner {
  /// Runs [files] of [package] and reports what failed.
  ///
  /// [files] are repository paths inside the package. A problem of the tests
  /// or of the tool is a [TestRunResult.startupError], not an exception.
  Future<TestRunResult> run(DartPackage package, List<RepoPath> files);
}

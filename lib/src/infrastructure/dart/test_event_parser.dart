/// Reads the machine-readable output of `dart test --reporter json` and
/// `flutter test --machine` (docs/specs/dart-toolchain.md, section 6).
library;

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/domain/dart/test_runner.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// The longest line decoded as an event: 1 MiB, inclusive. Longer lines
/// are skipped without [jsonDecode]; the splitter has already allocated
/// the string.
const int _maxLineLength = 1024 * 1024;

/// The longest startup error: it ends up in one finding message.
const int _maxErrorLength = 300;

const _loadFailure = 'Failed to load';

/// Turns the lines the test tool writes into a [TestRunResult].
///
/// A line is an event when it is at most 1 MiB, starts with `{`, decodes to
/// a JSON object and has a string `type`. Everything else, such as blank
/// lines, text, the JSON array `flutter test --machine` also writes, and
/// truncated objects, is ignored.
///
/// The parser is synchronous and pure: [add] each line, then [finish].
final class TestEventParser {
  /// Creates a parser for a run in the repository at [repoRoot].
  ///
  /// [repoRoot] must be resolved through symlinks, because the tools report
  /// real paths. A location the tool gives outside the repository, or not
  /// at all, is reported at [fallbackFile], line 1, column 1. [context]
  /// decides how paths and `file:` URLs are read; it defaults to the
  /// platform's.
  new({required this.repoRoot, required this.fallbackFile, p.Context? context})
    : _context = context ?? p.context;

  /// The repository root, symlinks resolved.
  final String repoRoot;

  /// Where a location that cannot be mapped is reported.
  final RepoPath fallbackFile;

  final p.Context _context;

  /// The suite path of each suite id.
  final Map<int, String> _suites = {};

  /// The tests that started and have not finished, by id.
  final Map<int, _StartedTest> _started = {};

  final List<FailedTest> _failures = [];

  /// The loader pseudo-tests that did not succeed, in order.
  final List<_StartedTest> _failedLoaders = [];

  var _realTestsStarted = 0;
  var _sawErrorEvent = false;

  /// Reads one line of standard output.
  void add(String line) {
    if (line.length > _maxLineLength || !line.startsWith('{')) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    switch (decoded['type']) {
      case 'suite':
        _onSuite(decoded);
      case 'testStart':
        _onTestStart(decoded);
      case 'error':
        _onError(decoded);
      case 'testDone':
        _onTestDone(decoded);
    }
  }

  void _onSuite(Map<String, Object?> event) {
    final suite = event['suite'];
    if (suite is! Map<String, Object?>) return;
    final id = suite['id'];
    final path = suite['path'];
    if (id is int && path is String) _suites[id] = path;
  }

  void _onTestStart(Map<String, Object?> event) {
    final test = event['test'];
    if (test is! Map<String, Object?>) return;
    final id = test['id'];
    final name = test['name'];
    if (id is! int || name is! String) return;
    final suiteId = test['suiteID'];
    final suitePath = suiteId is int ? _suites[suiteId] : null;
    final groups = test['groupIDs'];
    // The loader pseudo-test is named exactly after its suite, belongs to
    // no group and has no location. A real test whose name merely starts
    // with `loading ` is none of those, or is at least located.
    final isLoader =
        suitePath != null &&
        name == 'loading $suitePath' &&
        groups is List<Object?> &&
        groups.isEmpty &&
        test['url'] == null &&
        test['line'] == null;
    _started[id] = _StartedTest(
      name: name,
      loaderPath: isLoader ? suitePath : null,
      location: _Location.of(test),
    );
    if (!isLoader) _realTestsStarted++;
  }

  void _onError(Map<String, Object?> event) {
    _sawErrorEvent = true;
    final id = event['testID'];
    final text = event['error'];
    if (id is int && text is String) _started[id]?.errors.add(text);
  }

  void _onTestDone(Map<String, Object?> event) {
    final id = event['testID'];
    if (id is! int) return;
    final test = _started.remove(id);
    if (test == null) return;
    final result = event['result'];
    if (test.loaderPath != null) {
      if (result != 'success') _failedLoaders.add(test);
      return;
    }
    if (result != 'failure' && result != 'error') return;
    if (event['hidden'] == true || event['skipped'] == true) return;
    _failures.add(_failedTest(test));
  }

  FailedTest _failedTest(_StartedTest test) {
    final location = test.location;
    final file = location == null ? null : _toRepoPath(location.url);
    if (location == null || file == null) {
      return FailedTest(
        file: fallbackFile,
        line: 1,
        column: 1,
        name: test.name,
      );
    }
    return FailedTest(
      file: file,
      line: location.line,
      column: location.column,
      name: test.name,
    );
  }

  /// The repository path of the `file:` [url], or null when it is not a
  /// file inside the repository.
  RepoPath? _toRepoPath(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'file') return null;
      final path = uri.toFilePath(windows: _context.style == p.Style.windows);
      if (!_context.isWithin(repoRoot, path)) return null;
      final relative = _context.relative(path, from: repoRoot);
      return RepoPath(_context.split(relative).join('/'));
    } on FormatException {
      return null;
    }
    // `toFilePath` throws an `Error` for a URL it cannot turn into a path,
    // such as one with a fragment; there is no other way to ask.
    // ignore: avoid_catching_errors
    on UnsupportedError {
      return null;
    }
  }

  /// The result of the run, given the tool's [exitCode] and what it wrote to
  /// [standardError] (the caller keeps at most its first 64 KiB).
  ///
  /// Failures come sorted by file, line, column and name, whatever order the
  /// suites finished in. A result with a startup error is never a pass.
  TestRunResult finish({required int exitCode, String standardError = ''}) {
    final failures = [..._failures]
      ..sort((a, b) {
        final byFile = a.file.compareTo(b.file);
        if (byFile != 0) return byFile;
        final byLine = a.line.compareTo(b.line);
        if (byLine != 0) return byLine;
        final byColumn = a.column.compareTo(b.column);
        return byColumn != 0 ? byColumn : a.name.compareTo(b.name);
      });
    return TestRunResult(
      failures: failures,
      startupError: _startupError(failures, exitCode, standardError),
    );
  }

  String? _startupError(
    List<FailedTest> failures,
    int exitCode,
    String standardError,
  ) {
    if (_failedLoaders.isNotEmpty) {
      final loader = _failedLoaders.first;
      return _fromErrorText(loader.errors.join('\n')) ??
          'the test tool could not load ${loader.loaderPath}';
    }
    if (failures.isNotEmpty || exitCode == 0) return null;
    if (!_sawErrorEvent && _realTestsStarted == 0) {
      for (final line in const LineSplitter().convert(standardError)) {
        final text = line.trim();
        if (text.isNotEmpty) return _cut(text);
      }
    }
    return 'the test tool exited with code $exitCode';
  }

  /// The first line of [text] that is not the `Failed to load` banner, or
  /// the first line when every line is, with one trailing `.` or `:`
  /// removed; null when [text] has no line.
  String? _fromErrorText(String text) {
    final lines = [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.isEmpty) return null;
    var chosen = lines.firstWhere(
      (line) => !line.startsWith(_loadFailure),
      orElse: () => lines.first,
    );
    if (chosen.endsWith('.') || chosen.endsWith(':')) {
      chosen = chosen.substring(0, chosen.length - 1);
    }
    return _cut(chosen);
  }

  String _cut(String text) => text.length <= _maxErrorLength
      ? text
      : text.substring(0, _maxErrorLength);
}

/// A test between its `testStart` and its `testDone`.
final class _StartedTest {
  new({required this.name, required this.loaderPath, this.location});

  final String name;

  /// The suite path when this is the loader pseudo-test of that suite.
  final String? loaderPath;

  final _Location? location;

  /// The text of every `error` event so far.
  final List<String> errors = [];
}

/// Where a test is declared, as the tool reports it.
final class _Location {
  const new(this.url, this.line, this.column);

  /// The root location (where a helper-declared test was called from) when
  /// the tool gives one, else the declaration; null when there is no url.
  static _Location? of(Map<String, Object?> test) {
    final rootUrl = test['root_url'];
    if (rootUrl is String) {
      return _Location(
        rootUrl,
        _position(test['root_line']),
        _position(test['root_column']),
      );
    }
    final url = test['url'];
    if (url is String) {
      return _Location(url, _position(test['line']), _position(test['column']));
    }
    return null;
  }

  final String url;
  final int line;
  final int column;

  static int _position(Object? value) => value is int && value >= 1 ? value : 1;
}

# Affected Tests (0.3.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `0.3.0`: `tests/affected` on pre-push and CI, `why`, `l10n/unused-key`, a content-addressed cache, SARIF and JUnit reporters, and pub workspaces.

**Architecture:** Test selection is a pure function of the import graph built in 0.1.0. Running tests is the first feature that executes project code, isolated behind a `TestRunner` port. Syntactic facts become cacheable by blob id, which is what makes whole-package rules affordable.

**Tech Stack:** As plan 03. No new runtime dependency; SARIF and JUnit are written with `dart:convert` and a small XML writer of our own.

**Spec:** [`specs/rules.md`](../specs/rules.md) `tests/affected`, `l10n/unused-key`; [`specs/cli.md`](../specs/cli.md) 3.8, 7; [`specs/dart-toolchain.md`](../specs/dart-toolchain.md) 2, 3, 6; [`engineering/security.md`](../engineering/security.md) S1, S3.

## Global Constraints

- Everything in the Global Constraints of plans 01–03.
- The only executables started are `git` and the resolved SDK's `dart` or `flutter` (S1). Test file paths are passed as arguments after `--` where the tool accepts it.
- The cache lives under `<git common dir>/stagelatch/cache/` and nowhere else (S3). A cache failure of any kind is a miss, never an error.
- Cache keys include the blob id and the extractor version; a cache hit must be indistinguishable from recomputation. A test proves it.
- `tests/affected` never runs when the affected closure has uncommitted changes.

## Review Focus

- **A test that reaches a changed file only through a `package:` self-import, or only through a `part`.** Expected: selected. Pinned in Task 3.
- **Test tool output with lines that are not JSON** (build messages, warnings). Expected: ignored; only event objects are parsed. Pinned in Task 4.
- **A corrupted, truncated or unwritable cache.** Expected: recomputed silently; the verdict is unchanged. Pinned in Task 1.
- **A change that no test depends on.** Expected: no process is spawned and the check reports `ok`. Pinned in Task 5.
- **A workspace member whose `pubspec.lock` and package config live at the workspace root.** Expected: found there. Pinned in Task 9.

---

### Task 1: Content-addressed cache for facts

**Branch:** `feat/04-01-cache`

**Files:**
- Create: `lib/src/application/ports/cache.dart`, `lib/src/infrastructure/io/file_cache.dart`, `lib/src/infrastructure/dart/cached_facts.dart`, `lib/src/infrastructure/dart/facts_codec.dart`, `test/support/fake_cache.dart`
- Modify: `lib/src/cli/composition.dart`, `docs/engineering/security.md` (S3 table already lists the cache; confirm the path)
- Test: `test/infrastructure/io/file_cache_test.dart`, `test/infrastructure/dart/cached_facts_test.dart`, `facts_codec_test.dart`

**Interfaces:**
- Produces: `Cache { Future<String?> read(String namespace, String key); Future<void> write(String namespace, String key, String value) }`; `FileCache({required String directory})`; `const int factsFormatVersion`; `String encodeFacts(DartFileFacts)`, `DartFileFacts? decodeFacts(String)`; `CachedFacts(SyntacticFacts inner, Cache cache)` with `Future<DartFileFacts?> extract(String blobId, String source, RepoPath path)`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('a value written is read back; an unknown key is null', () async { /* ... */ });
test('keys are stored under <namespace>/<first two characters>/<key>', () async { /* ... */ });
test('a key with path separators or dots is rejected', () async { expect(() => cache.write('facts', '../x', 'v'), throwsArgumentError); });
test('writes are atomic: a reader never sees a partial file', () async { /* write to a temp name, then rename */ });
test('a corrupted entry is a miss', () async { /* overwrite the file with garbage; decodeFacts returns null */ });
test('an unwritable directory makes write a no-op and read a miss', () async { /* ... */ }, testOn: '!windows');
test('facts round-trip through the codec', () { expect(decodeFacts(encodeFacts(facts)), facts); });
test('a different format version is a miss', () { /* ... */ });
test('a cache hit equals recomputation, including locations relative to the requested path', () async {
  // same blob at two paths: locations must carry the requested path, so the path is not cached
});
test('the second extraction of the same blob does not call the inner extractor', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Namespace is `facts-v<factsFormatVersion>`; the key is the blob id. Cached values store positions only; the path is re-attached on read. The cache directory is created lazily and its containment under the git common directory is verified.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(cache): cache syntactic facts by blob id`

### Task 2: Identifier facts and `l10n/unused-key`

**Branch:** `feat/04-02-l10n-unused-key`

**Files:**
- Modify: `lib/src/infrastructure/dart/syntactic_facts.dart`, `facts_codec.dart` (bump `factsFormatVersion`), `lib/src/checks/l10n/l10n_check.dart`
- Create: `lib/src/checks/l10n/unused_keys.dart`
- Test: `test/infrastructure/dart/identifiers_test.dart`, `test/checks/l10n/unused_keys_test.dart`

**Interfaces:**
- Produces: `SyntacticFacts.extract` fills `identifiers`; the `l10n/unused-key` descriptor (default `warning`); `Future<List<Finding>> unusedKeyFindings(CheckContext context, L10nSetup setup, ArbDocument template, DartPackage package)`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('identifiers are collected from code, not from comments or strings', () {
  expect(ids("void f() { l10n.checkoutTitle; } // unusedInComment 'unusedInString'"), containsAll(['f', 'l10n', 'checkoutTitle']));
  expect(ids("// unusedInComment\nvar s = 'unusedInString';"), isNot(contains('unusedInComment')));
});
test('a key referenced nowhere is reported at the template key', () async {
  expect(f.single.message, 'Key "legacyBanner" is not referenced by any Dart file.');
  expect(f.single.severity, Severity.warning);
});
test('a reference in a generated file does not count', () async { /* under the l10n output dir; *.g.dart */ });
test('a reference in another package does not count', () async { /* ... */ });
test('the rule runs when a Dart file changed even if no ARB did', () async { /* removing the last use */ });
test('the rule scans the whole package, not the changeset', () async { /* the only use is in an unchanged file */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Facts for all package files are requested concurrently and served by the cache.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add l10n/unused-key`

### Task 3: Affected test selection

**Branch:** `feat/04-03-affected-selection`

**Files:**
- Create: `lib/src/domain/dart/affected_tests.dart`
- Test: `test/domain/dart/affected_tests_test.dart`

**Interfaces:**
- Consumes: `ImportGraph`, `ChangeSet`, `PackageMap`, `isTestFile`.
- Produces: `AffectedTests select({required ImportGraph graph, required ChangeSet changes, required PackageMap packages})`; `AffectedTests { List<RepoPath> testFiles; Set<RepoPath> closure; Map<DartPackage, List<RepoPath>> byPackage }` where `closure` is every file on any import chain from a selected test to a changed file, tests included.

- [ ] **Step 1: Write the failing tests.**

```dart
test('a changed test file selects itself', () { /* ... */ });
test('a test importing a changed file directly or transitively is selected', () { /* ... */ });
test('package: self-imports and part files are followed', () { /* ... */ });
test('a test that does not depend on any change is not selected', () { /* ... */ });
test('a deleted source file selects the tests that still import it', () {
  // the graph keeps the dangling edge, so the importer is found and its run fails to compile
});
test('closure contains the chain files and nothing else', () { /* ... */ });
test('results are sorted and grouped by package', () { /* ... */ });
test('files outside test/ ending in _test.dart are not tests', () { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** as a reverse breadth-first walk from the changed files, recording predecessors so the closure can be reconstructed.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(domain): select tests affected by a changeset`

### Task 4: Test runner

**Branch:** `feat/04-04-test-runner`

**Files:**
- Create: `lib/src/domain/dart/test_runner.dart`, `lib/src/infrastructure/dart/process_test_runner.dart`, `test_event_parser.dart`, `test/support/fake_test_runner.dart`
- Create: `test/fixtures/test_events/*.jsonl` (recorded output: all pass, one failure, compile error, noise lines), `test/fixtures/dart_app/test/`
- Test: `test/infrastructure/dart/test_event_parser_test.dart`, `process_test_runner_test.dart`

**Interfaces:**
- Produces: `TestFailure { RepoPath file; int line; String name }`; `TestRunResult { List<TestFailure> failures; String? startupError }`; `TestRunner { Future<TestRunResult> run(DartPackage package, List<RepoPath> files) }`; `TestRunResult parseTestEvents(Iterable<String> lines, {required RepoPath? packageRoot})`; `ProcessTestRunner({required ResolvedSdk sdk, required String repoRoot})`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('all passing produces no failure', () { expect(parse('all_pass.jsonl').failures, isEmpty); });
test('a failing test is reported with file, line and full name', () {
  expect(parse('one_failure.jsonl').failures.single, TestFailure(file: RepoPath('test/cart_test.dart'), line: 12, name: 'cart adds an item'));
});
test('hidden and skipped tests are not failures', () { /* loading tests, skip: true */ });
test('lines that are not JSON objects are ignored', () { expect(parse('noise.jsonl').failures, hasLength(1)); });
test('a run with no test event and a non-zero exit is a startup error with the first error line', () {
  expect(parse('compile_error.jsonl').startupError, isNotNull);
});
test('paths are made repository-relative from the package root', () { /* packages/ui/test/a_test.dart */ });
test('dart test is used for a Dart package and flutter test for a Flutter one', () async { /* inspect the spawned command */ });
test('the process runs in the package directory with an argument list', () async { /* S1 */ });
test('the fixture package: one failing test is found end to end', () async { /* real run */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Commands: `<sdk>/bin/dart test --reporter json -- <files>` and `<flutter> test --machine <files>`. Confirm the exact flags and the event field names against the SDK in use before recording fixtures; note the SDK version in the fixture directory's README. Output is consumed as a line stream, not buffered whole.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(dart): add test runner over machine-readable output`

### Task 5: The `tests/affected` rule

**Branch:** `feat/04-05-tests-affected`

**Files:**
- Modify: `lib/src/domain/check.dart` (add `TestRunner get tests` and `Future<Set<RepoPath>> get diverging` to `CheckContext`), `lib/src/checks/tests/tests_check.dart`, `lib/src/application/pipeline/pipeline_check_context.dart`, `lib/src/cli/composition.dart`
- Create: `lib/src/checks/tests/affected_rule.dart`
- Test: `test/checks/tests/affected_rule_test.dart`, `test/acceptance/ac24_affected_dirty_test.dart`

**Interfaces:**
- Consumes: `select`, `TestRunner`, `CheckContext.importGraph`, `CheckContext.diverging`.
- Produces: the `tests/affected` descriptor; `Future<List<Finding>> affectedFindings(CheckContext context)`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('no affected test: no run and no finding', () async { expect(runner.calls, isEmpty); });
test('one finding per failed test at its line', () async {
  expect(f.single.message, 'Test failed: cart adds an item.');
  expect(f.single.location, Location(RepoPath('test/cart_test.dart'), const Position(12, 1), const Position(12, 1)));
});
test('a startup error is one finding at the first affected file', () async {
  expect(f.single.message, startsWith('Tests could not be run: '));
});
test('uncommitted changes in the closure skip the run with a warning', () async {
  expect(runner.calls, isEmpty);
  expect(f.single.message, 'Affected tests were not run: 2 affected file(s) have uncommitted changes.');
  expect(f.single.severity, Severity.warning);
});
test('uncommitted changes outside the closure do not skip the run', () async { /* ... */ });
test('each package is run once with its own files', () async { /* two packages */ });
test('the rule does not run on pre-commit even if selected', () async { /* EntryKind.preCommit */ });
```

AC-24: push a commit that breaks a test: blocked with the failure. Same push while the test file has an unstaged edit: push allowed, warning printed.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/rules.md` `tests/affected`.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add tests/affected`

### Task 6: `why`

**Branch:** `feat/04-06-why`

**Files:**
- Create: `lib/src/application/why/why.dart`, `lib/src/cli/commands/why_command.dart`
- Test: `test/application/why/why_test.dart`, `test/cli/why_command_test.dart`

**Interfaces:**
- Produces: `WhyResult { RepoPath test; List<List<RepoPath>> chains }`; `Why(...)` with `Future<WhyResult> explain(RepoPath testFile, {String? baseRef})`; `String renderWhy(WhyResult)`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('prints one shortest chain per changed file that reaches the test', () {
  expect(renderWhy(result), '''
test/checkout/cart_test.dart is affected by 1 changed file:

lib/checkout/cart.dart (changed)
  imported by lib/checkout/cart_controller.dart
  imported by test/checkout/cart_test.dart
''');
});
test('an unaffected test says so', () { expect(renderWhy(none), 'test/x_test.dart is not affected by the current changes.\n'); });
test('a path that is not a test file is a usage error', () async { expect(await run(['why', 'lib/a.dart']), 64); });
test('the default base is the upstream, else the merge-base with the remote default branch', () async { /* ... */ });
test('the changeset is base..index, so staged changes count', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** with `ImportGraph.shortestChain`.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(cli): add why command`

### Task 7: SARIF reporter

**Branch:** `feat/04-07-sarif`

**Files:**
- Create: `lib/src/infrastructure/reporters/sarif_reporter.dart`, `test/goldens/sarif/*.sarif`
- Test: `test/infrastructure/reporters/sarif_reporter_test.dart`

**Interfaces:**
- Produces: `SarifReporter(StringSink out, {required String toolVersion, required Map<RuleId, RuleDescriptor> descriptors}) implements Reporter`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('matches the golden: version 2.1.0, one run, driver name and version', () { /* ... */ });
test('rules lists each rule that produced a result, once, sorted', () { /* ... */ });
test('levels map from severity; regions are 1-based', () { /* ... */ });
test('analyze rules without a descriptor get the rule id as short description', () { /* ... */ });
test('several pipeline runs are merged into one SARIF run without duplicate results', () { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/cli.md` section 7.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(reporters): add SARIF reporter`

### Task 8: JUnit reporter

**Branch:** `feat/04-08-junit`

**Files:**
- Create: `lib/src/infrastructure/reporters/junit_reporter.dart`, `xml_writer.dart`, `test/goldens/junit/*.xml`
- Test: `test/infrastructure/reporters/junit_reporter_test.dart`, `xml_writer_test.dart`

**Interfaces:**
- Produces: `String escapeXml(String text, {required bool attribute})`; `JunitReporter(StringSink out) implements Reporter`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('XML escaping covers the five entities and drops characters XML 1.0 forbids', () {
  expect(escapeXml('<a & "b">', attribute: true), '&lt;a &amp; &quot;b&quot;&gt;');
  expect(escapeXml('a\u0000b\u000bc', attribute: false), 'abc');
});
test('one testcase per check; error findings are failures; warnings go to system-out', () { /* golden */ });
test('testsuite counts tests and failures', () { /* tests="3" failures="1" */ });
test('a message containing ]]> or markup cannot break the document', () { /* parse the output back */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** No XML dependency: elements are written through `xml_writer.dart`, which is the only place that emits `<` or `&`.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(reporters): add JUnit reporter`

### Task 9: Pub workspaces

**Branch:** `feat/04-09-workspaces`

**Files:**
- Modify: `lib/src/domain/package_map.dart`, `lib/src/application/packages/package_map_builder.dart`, `lib/src/checks/pubspec/pubspec_check.dart`, the toolchain adapter's package config lookup
- Create: `test/fixtures/workspace/`
- Test: `test/application/packages/workspace_test.dart`, `test/checks/pubspec/workspace_lock_test.dart`, `test/acceptance/workspace_test.dart`

**Interfaces:**
- Produces: `DartPackage.workspaceRoot` (`RepoPath?`, or a marker for the repository root) and `PackageMap.resolutionRootOf(DartPackage)`: the directory that holds the package's `pubspec.lock` and `.dart_tool/package_config.json`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('a member with resolution: workspace resolves to the root that lists it', () async { /* ... */ });
test('workspace globs in the root pubspec are expanded against the snapshot', () async { /* packages/* */ });
test('a nested workspace resolves to the outermost root', () async { /* ... */ });
test('lockfile-out-of-sync reads the root pubspec.lock for a member', () async { /* ... */ });
test('the missing package config error names the workspace root', () async { /* ... */ });
test('a package without resolution: workspace is unaffected', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/dart-toolchain.md` section 2.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(packages): support pub workspaces`

### Task 10: Documentation and 0.3.0

**Branch:** `docs/04-10-release`

**Files:**
- Modify: `README.md`, `docs/rules.md`, `action.yml` (document `sarif`), `stagelatch.yaml`, `docs/plans/README.md`

- [ ] **Step 1: Update the README:** `tests/affected` and its dirty-closure rule, `why`, the SARIF upload snippet for code scanning, workspaces, the cache location and how to clear it.
- [ ] **Step 2: Re-run the benchmark** with a warm and a cold cache and add both rows.
- [ ] **Step 3: Enable** `tests/affected` on pre-push in this repository's own config.
- [ ] **Step 4: Verify** all four commands and `dart pub publish --dry-run`.
- [ ] **Step 5: Commit.** `docs: document 0.3.0`
- [ ] **Step 6: Release** `0.3.0` per workflow section 8.

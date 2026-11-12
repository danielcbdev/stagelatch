# Core (0.1.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `0.1.0`: `format` with safe autofix, `analyze` on the affected scope with overlays, `sensitive-files`, `run pre-push`, `ci`, `doctor`, JSON and GitHub reporters, SDK resolution, multi-package repositories and inline suppression.

**Architecture:** The Dart toolchain enters behind the `DartToolchain` port, implemented by the mechanism the spike selected. The pipeline gains the fix phase for real, an inline-ignore filter, and two more entry points that reuse the same use case with commit snapshots.

**Tech Stack:** As plan 01, plus the Dart toolchain dependencies recorded in ADR-0008 after the spike, and `crypto`.

**Spec:** [`specs/dart-toolchain.md`](../specs/dart-toolchain.md); [`specs/git.md`](../specs/git.md) 4.2, 4.3, 6; [`specs/cli.md`](../specs/cli.md) 3.4–3.6, 5, 6; [`specs/rules.md`](../specs/rules.md) `format`, `analyze`, `sensitive-files`, `stagelatch`; [`specs/baseline-and-suppression.md`](../specs/baseline-and-suppression.md) 1–3.

**Precondition:** `docs/spike/report.md` exists and ADR-0008 names the mechanism. If not, stop.

## Global Constraints

- Everything in plan 01's Global Constraints.
- `package:analyzer`, `package:dart_style` and the analysis server protocol are referenced only under `lib/src/infrastructure/dart/`. The layering test is extended to enforce it.
- `format` and `analyze` results equal those of the resolved SDK's `dart format` and `dart analyze` (ADR-0008). The contract tests of Task 7 are the proof and may not be weakened.
- The resolved SDK is outside the repository (S2).
- Fixes use only `hash-object -w`, `update-index --index-info` and `checkout-index` (S4).
- JSON output is byte-identical across runs once `durationMs` fields are removed.

## Review Focus

- **An unstaged edit in a file that a staged file imports.** Expected: the verdict ignores it. Pinned in Task 7 (contract test) and Task 15 (AC-18).
- **The first push of a repository, with no remote-tracking refs at all.** Expected: base is the empty tree and every file counts as added. Pinned in Task 12.
- **An analyzer message containing a newline or `::`.** Expected: the GitHub reporter escapes it so no extra workflow command is emitted. Pinned in Task 3.
- **A fix requested while `.git/index.lock` exists.** Expected: exit 70 naming the lock, index and working tree untouched. Pinned in Task 8.
- **A project that never ran `dart pub get`.** Expected: usage error with the command to run, only when Dart analysis is actually needed. Pinned in Task 7 and Task 15.

---

### Task 1: Inline ignore filter

**Branch:** `feat/02-01-inline-ignore`

**Files:**
- Create: `lib/src/application/pipeline/inline_ignore.dart`
- Modify: `lib/src/application/pipeline/pipeline.dart`, `finding_filters.dart`
- Test: `test/application/pipeline/inline_ignore_test.dart`

**Interfaces:**
- Consumes: `Finding`, `SnapshotFiles`, `ChangeSet`, `CheckCatalog`.
- Produces: `List<IgnoreDirective> scanIgnores(String text, {required String commentOpener})`; `IgnoreDirective { int line; List<IgnoreId> ids }`; `IgnoreId { String text; int column }`; `String? commentOpenerFor(RepoPath path)` returning `//`, `#` or null; `Future<IgnoreOutcome> applyInlineIgnores(List<Finding> findings, {required SnapshotFiles snapshot, required ChangeSet changes, required CheckCatalog catalog})`; `IgnoreOutcome { List<Finding> kept; int suppressed; List<Finding> invalid }`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('a directive covers its own line and the next', () {
  final d = scanIgnores('a\n// stagelatch:ignore tests/solo\nb\n', commentOpener: '//').single;
  expect(d.line, 2); expect(d.ids.single.text, 'tests/solo'); expect(d.ids.single.column, 22);
});
test('several ids, spaces around commas, and trailing free text', () {
  final ids = scanIgnores('x(); // stagelatch:ignore a/b , c/d flaky, see #42', commentOpener: '//').single.ids;
  expect(ids.map((i) => i.text), ['a/b', 'c/d']);
});
test('the marker must directly follow the comment opener', () {
  expect(scanIgnores('// see stagelatch:ignore a/b', commentOpener: '//'), isEmpty);
  expect(scanIgnores('//stagelatch:ignore a/b', commentOpener: '//'), hasLength(1));
});
test('YAML uses #', () { /* '# stagelatch:ignore pubspec/dependency-overrides' */ });
test('files without a comment form have no inline ignore', () {
  expect(commentOpenerFor(RepoPath('lib/l10n/app_en.arb')), isNull);
});
test('a finding on line n or n+1 with a named rule is suppressed; others are kept', () async { /* ... */ });
test('an unknown id yields stagelatch/invalid-ignore at the id, in changed files only', () async {
  expect(outcome.invalid.single.message, 'Unknown rule "pubspec/nope" in stagelatch:ignore.');
  expect(outcome.invalid.single.severity, Severity.warning);
});
test('ids under analyze/ are always accepted', () async { /* ... */ });
test('a one-megabyte line is scanned in linear time', () { /* completes; S6 */ });
```

- [ ] **Step 2: Run.** Expected: FAIL, `scanIgnores` undefined.
- [ ] **Step 3: Implement** with a hand-written scan per line (`indexOf` of the opener, then the marker); no regular expression. Insert the filter in the chain after `exclude` and before the baseline position. `invalid-ignore` findings bypass inline suppression.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(pipeline): add inline stagelatch:ignore suppression`

### Task 2: JSON reporter

**Branch:** `feat/02-02-json-reporter`

**Files:**
- Create: `lib/src/infrastructure/reporters/json_reporter.dart`, `test/goldens/json/*.json`
- Modify: `lib/src/cli/commands/run_command.dart` (`--reporter`), `lib/src/cli/runner.dart` (error object)
- Test: `test/infrastructure/reporters/json_reporter_test.dart`, `test/cli/reporter_option_test.dart`

**Interfaces:**
- Consumes: `Reporter`, `RunReport`.
- Produces: `JsonReporter(StringSink out, {required String toolVersion}) implements Reporter`; `String renderErrorJson({required String kind, required String message, required int exitCode})`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('one run renders the object of specs/cli.md section 5, keys in order', () { /* golden: single.json */ });
test('several runs render a "runs" array with a top-level verdict and exit code', () { /* golden: multi.json */ });
test('output is identical across runs after removing durationMs', () { /* two reports differing only in durations */ });
test('exit 64, 70 and 78 print the error object on stdout and the message on stderr', () async {
  expect(out.toString(), '{"schemaVersion":1,"error":{"kind":"usage","message":"Unknown hook \\"x\\"."},"exitCode":64}\n');
});
test('strings are encoded by the JSON encoder, never concatenated', () { /* message with quotes, backslash, newline */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** with `JsonEncoder.withIndent('  ')` over a `LinkedHashMap` built in the documented key order; the error object is rendered compact.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(reporters): add JSON reporter`

### Task 3: GitHub reporter

**Branch:** `feat/02-03-github-reporter`

**Files:**
- Create: `lib/src/infrastructure/reporters/github_reporter.dart`
- Test: `test/infrastructure/reporters/github_reporter_test.dart`

**Interfaces:**
- Produces: `String escapeWorkflowData(String)`; `String escapeWorkflowProperty(String)`; `GithubReporter(StringSink out) implements Reporter`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('data escapes percent, CR and LF', () { expect(escapeWorkflowData('50%\r\nx'), '50%25%0D%0Ax'); });
test('properties also escape colon and comma', () { expect(escapeWorkflowProperty('a:b,c'), 'a%3Ab%2Cc'); });
test('an error renders one command line', () {
  expect(lines.first, '::error file=pubspec.yaml,line=14,col=5,endLine=14,endColumn=26,title=pubspec/path-dependency::Dependency "design_system" uses a path that is not a package in this repository: ../design_system.');
});
test('a warning uses ::warning', () { /* ... */ });
test('a message carrying a newline and a workflow command cannot start a new command', () {
  // message: 'x\n::set-output name=a::b'
  expect(out.toString().split('\n').where((l) => l.startsWith('::')).length, 1);
});
test('the console summary line follows the commands', () { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Paths containing `,` or `:` go through `escapeWorkflowProperty`.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(reporters): add GitHub workflow command reporter`

### Task 4: SDK locator

**Branch:** `feat/02-04-sdk-locator`

**Files:**
- Create: `lib/src/application/ports/sdk_locator.dart`, `lib/src/infrastructure/dart/file_sdk_locator.dart`, `test/support/fake_sdk_locator.dart`
- Test: `test/infrastructure/dart/file_sdk_locator_test.dart`

**Interfaces:**
- Consumes: `Config`, `Environment`, `RepoLayout`.
- Produces: `enum SdkSource { sdkPath, fvm, path }`; `ResolvedSdk { String root; String dartExecutable; String? flutterExecutable; String version; SdkSource source }`; `SdkLocator { Future<ResolvedSdk> locate(Config config) }`; `FileSdkLocator({required String repoRoot, required Environment environment})`.

- [ ] **Step 1: Write the failing tests,** each building SDK-shaped directories in a temp folder.

```dart
test('sdk_path wins over FVM and PATH', () async { expect(sdk.source, SdkSource.sdkPath); });
test('a Flutter root resolves to bin/cache/dart-sdk and exposes flutter', () async {
  expect(sdk.root, endsWith('bin/cache/dart-sdk')); expect(sdk.flutterExecutable, isNotNull); expect(sdk.version, '3.13.4');
});
test('.fvm/flutter_sdk is used when present', () async { expect(sdk.source, SdkSource.fvm); });
test('.fvmrc resolves under FVM_CACHE_PATH, else under the home directory', () async { /* ... */ });
test('PATH is searched in order for dart or dart.exe', () async { expect(sdk.source, SdkSource.path); });
test('an SDK inside the repository is rejected', () async {
  expect(error.message, startsWith('The Dart SDK must be outside the repository: '));
});
test('a symlink in the repository that points outside is accepted', () async { /* .fvm/flutter_sdk -> outside */ }, testOn: '!windows');
test('each unresolved source has its own message', () async {
  expect(e1.message, 'sdk_path "nope" is not a Dart or Flutter SDK.');
  expect(e3.message, 'No Dart SDK found. Install Dart or set sdk_path.');
});
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/dart-toolchain.md` section 1. Containment is checked on resolved real paths.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(dart): add SDK locator with FVM support and containment rule`

### Task 5: Package map

**Branch:** `feat/02-05-package-map`

**Files:**
- Create: `lib/src/application/packages/package_map_builder.dart`
- Modify: `lib/src/domain/package_map.dart` (implementation of the lookup)
- Test: `test/application/packages/package_map_builder_test.dart`

**Interfaces:**
- Produces: `Future<PackageMap> buildPackageMap(SnapshotFiles snapshot, Documents documents)`; `DartPackage { RepoPath? root; String name; bool usesFlutter }` where a null root is the repository root.

- [ ] **Step 1: Write the failing tests.**

```dart
test('a file belongs to the nearest enclosing pubspec', () async {
  final map = await buildPackageMap(FakeSnapshotFiles({'pubspec.yaml': 'name: app\n', 'packages/ui/pubspec.yaml': 'name: ui\n', 'packages/ui/lib/a.dart': '', 'lib/b.dart': ''}), docs);
  expect(map.packageOf(RepoPath('packages/ui/lib/a.dart'))!.name, 'ui');
  expect(map.packageOf(RepoPath('lib/b.dart'))!.name, 'app');
});
test('a file outside every package has none', () async { /* no root pubspec */ });
test('usesFlutter is read from an sdk: flutter dependency', () async { /* ... */ });
test('an unparseable pubspec still defines a package, named after its directory', () async { /* ... */ });
test('packages are sorted by root', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Lookup walks the path's parents, deepest first.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(packages): map files to their nearest pubspec`

### Task 6: Directive facts and the import graph

**Branch:** `feat/02-06-import-graph`

**Files:**
- Create: `lib/src/domain/dart/import_graph.dart`, `lib/src/infrastructure/dart/syntactic_facts.dart`
- Modify: `lib/src/domain/check.dart` (add `Future<ImportGraph> get importGraph` to `CheckContext`), `test/support/fake_check_context.dart`
- Test: `test/domain/dart/import_graph_test.dart`, `test/infrastructure/dart/syntactic_facts_test.dart`

**Interfaces:**
- Consumes: `Directive`, `DirectiveKind`, `DartFileFacts`, `PackageMap`.
- Produces: `ImportGraph.build({required Map<RepoPath, List<Directive>> directives, required PackageMap packages})`; `Set<RepoPath> dependentsOf(Set<RepoPath> files)`; `List<RepoPath>? shortestChain(RepoPath from, RepoPath to)`; `SyntacticFacts({required List<String> testFunctions})` with `DartFileFacts? extract(String source, RepoPath path)`, filling `directives` only in this version.

- [ ] **Step 1: Write the failing tests.**

```dart
test('relative, package and part URIs become edges; external ones are ignored', () {
  final g = graph({
    'lib/a.dart': ["import 'b.dart';", "import 'package:app/src/c.dart';", "import 'dart:io';", "import 'package:http/http.dart';"],
    'lib/b.dart': [], 'lib/src/c.dart': ["part 'c.g.dart';"], 'lib/src/c.g.dart': ["part of 'c.dart';"],
  });
  expect(g.dependentsOf({RepoPath('lib/src/c.g.dart')}).map((p) => p.value), ['lib/a.dart', 'lib/src/c.dart', 'lib/src/c.g.dart']);
});
test('conditional imports contribute every branch', () { /* import 'a.dart' if (dart.library.io) 'b.dart'; */ });
test('cycles terminate', () { /* a -> b -> a */ });
test('importers of a file that is absent from the snapshot are still found', () {
  // lib/a.dart imports 'gone.dart', which is not a node
  expect(g.dependentsOf({RepoPath('lib/gone.dart')}).map((p) => p.value), ['lib/a.dart', 'lib/gone.dart']);
});
test('dependentsOf includes the inputs and is sorted', () { /* ... */ });
test('shortestChain is breadth-first and breaks ties by path order', () {
  expect(g.shortestChain(RepoPath('lib/x.dart'), RepoPath('test/x_test.dart'))!.map((p) => p.value),
      ['lib/x.dart', 'lib/a.dart', 'test/x_test.dart']);   // not via lib/b.dart
});
test('shortestChain is null when unreachable', () { /* ... */ });
test('extract returns directives with locations and null on a syntax error', () { /* ... */ });
test('directive-like text in comments and strings is ignored', () { /* "// import 'x.dart';" */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** `SyntacticFacts` uses the extractor chosen in the spike (Task 7, step 3 of plan 00). The graph stores reverse adjacency in sorted sets.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(dart): add directive facts and import graph`

### Task 7: Dart toolchain adapter

**Branch:** `feat/02-07-dart-toolchain`

**Files:**
- Create: `lib/src/application/ports/dart_toolchain_factory.dart`, `test/support/fake_dart_toolchain.dart`
- Create: under `lib/src/infrastructure/dart/`, the adapter for the mechanism recorded in ADR-0008
- Create: `test/fixtures/dart_app/` (a dependency-free Dart package: `pubspec.yaml`, `analysis_options.yaml` with `page_width: 100`, `lib/`), `test/support/oracle.dart`
- Modify: `test/architecture/layering_test.dart` (toolchain packages allowed only under `infrastructure/dart/`)
- Test: `test/infrastructure/dart/toolchain_contract_test.dart`

**Interfaces:**
- Consumes: `ResolvedSdk`, `SyntacticFacts`, `DartToolchain`.
- Produces: `DartToolchainFactory { Future<DartToolchain> create({required ResolvedSdk sdk, required String repoRoot, required Map<RepoPath, String?> overlays, required PackageMap packages}) }` where a null overlay value means "deleted in the snapshot"; `DartToolchain.close()` added to the port; `FakeDartToolchain` recording `diagnose` and `format` calls; `Future<OracleResult> runOracle(String packageDir)` in test support, which runs the SDK's `dart analyze --format=json` and `dart format --output=show` on a directory.

- [ ] **Step 1: Write the failing contract tests.** They never mention the mechanism.

```dart
test('diagnostics equal dart analyze on a tree identical to the snapshot', () async {
  // fixture gets one error, one warning, one lint written to disk
  expect(await toolchain.diagnose(files), equalsOracle(await runOracle(fixture)));
});
test('an overlay replaces the file on disk', () async {
  // disk: lib/a.dart has an error; overlay: clean content
  expect(await toolchain.diagnose({RepoPath('lib/a.dart')}), isEmpty);
});
test('an unstaged error in an imported file does not leak', () async {
  // disk: lib/dep.dart broken; overlay: lib/dep.dart with snapshot (valid) content
  expect(await toolchain.diagnose({RepoPath('lib/uses_dep.dart')}), isEmpty);
});
test('a null overlay hides a file that exists on disk', () async {
  expect((await toolchain.diagnose({RepoPath('lib/uses_gone.dart')})).single.code, 'uri_does_not_exist');
});
test('only requested files are reported', () async { /* ... */ });
test('ignore comments and analysis_options are honored', () async { /* ... */ });
test('format equals dart format, including page_width from analysis_options', () async {
  expect(((await toolchain.format(path, source)) as Formatted).text, (await runOracle(fixture)).formatted[path.value]);
});
test('format keeps CRLF when the input uses CRLF', () async { /* ... */ });
test('format of unparseable source is Unparseable', () async { /* ... */ });
test('a package without .dart_tool/package_config.json is a usage error', () async {
  expect(e.message, 'Missing .dart_tool/package_config.json. Run: dart pub get');
});
test('close ends every child process', () async { /* ... */ });
```

- [ ] **Step 2: Run** `dart test test/infrastructure/dart/toolchain_contract_test.dart`. Expected: FAIL, no adapter.
- [ ] **Step 3: Implement** the mechanism of ADR-0008 per `specs/dart-toolchain.md` sections 4, 5 and 7. Overlays are installed once, before the first request. `facts` delegates to `SyntacticFacts` and must not start the expensive part. Every protocol call or analyzer API call has a comment saying what it does and why that call was chosen.
- [ ] **Step 4: Run** all four commands on all matrix cells. Expected: PASS. A contract test that fails on one OS or on Dart beta is a blocker, not a skip.
- [ ] **Step 5: Commit.** `feat(dart): add toolchain adapter with snapshot overlays`

### Task 8: Applying fixes to the index

**Branch:** `feat/02-08-apply-fixes`

**Files:**
- Modify: `lib/src/infrastructure/git/git_cli_repository.dart`, `lib/src/cli/commands/run_command.dart` (`--no-fix`)
- Test: `test/infrastructure/git/apply_fixes_test.dart`

**Interfaces:**
- Produces: `GitCliRepository.applyFixes(List<Fix> fixes) -> Future<List<AppliedFix>>`, working for `IndexSnapshot`; `StateError` when called for a commit snapshot.

- [ ] **Step 1: Write the failing tests.**

```dart
test('a clean file is fixed in the index and in the working tree', () async {
  expect(await repo.git(['show', ':a.dart']), 'fixed\n'); expect(await repo.read('a.dart'), 'fixed\n');
  expect(applied.single.worktreeUpdated, isTrue);
});
test('a partially staged file is fixed in the index only', () async {
  // index: 'staged\n'; working tree: 'staged\nunstaged\n'
  expect(await repo.git(['show', ':a.dart']), 'fixed\n'); expect(await repo.read('a.dart'), 'staged\nunstaged\n');
  expect(applied.single.worktreeUpdated, isFalse);
});
test('the executable mode is preserved', () async { expect(await repo.git(['ls-files', '-s', 'run.dart']), startsWith('100755 ')); });
test('with core.autocrlf the index stays LF and the working tree gets CRLF', () async { /* AC-10 */ });
test('paths with spaces and non-ASCII characters work', () async { /* ... */ });
test('a held index.lock raises InternalException and changes nothing', () async {
  // create .git/index.lock by hand
  expect(e.message, contains('index.lock')); expect(await repo.git(['show', ':a.dart']), 'before\n');
});
test('several fixes are applied by a single update-index call', () async { /* count spawns */ });
```

- [ ] **Step 2: Run.** Expected: FAIL, `applyFixes` throws `UnsupportedError`.
- [ ] **Step 3: Implement** the four steps of `specs/git.md` section 6, in that order.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(git): apply fixes through the index without touching unstaged work`

### Task 9: The `format` check

**Branch:** `feat/02-09-format-check`

**Files:**
- Create: `lib/src/checks/format/format_check.dart`, `first_difference.dart`
- Modify: `lib/src/application/pipeline/pipeline.dart` (drop fixes for excluded paths), `check_registry.dart` wiring in `composition.dart`
- Test: `test/checks/format/format_check_test.dart`, `first_difference_test.dart`

**Interfaces:**
- Consumes: `DartToolchain.format`, `FormatSettings`.
- Produces: `FormatCheck implements Check` (`id: 'format'`, `phase: CheckPhase.fix`, rule `format/unformatted`, `fixable: true`); `Position firstDifference(String a, String b)`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('firstDifference returns the 1-based line and column', () {
  expect(firstDifference('a\nbc\n', 'a\nbd\n'), const Position(2, 2));
  expect(firstDifference('a', 'a\n'), const Position(1, 2));
});
test('an unformatted file yields a finding at the first difference and a fix', () async {
  expect(result.findings.single.message, 'File is not formatted.');
  expect(result.fixes.single.content, formatted);
});
test('a formatted file, a deleted file and a non-Dart file yield nothing', () async { /* ... */ });
test('an unparseable file yields nothing', () async { /* FakeDartToolchain returns Unparseable */ });
test('the pipeline applies no fix to an excluded path and drops its finding', () async { /* ... */ });
test('on a commit snapshot the finding blocks and nothing is applied', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Files are formatted concurrently and results consumed in path order.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add format check with index autofix`

### Task 10: The `analyze` check

**Branch:** `feat/02-10-analyze-check`

**Files:**
- Create: `lib/src/checks/analyze/analyze_check.dart`, `analysis_scope.dart`
- Test: `test/checks/analyze/analysis_scope_test.dart`, `analyze_check_test.dart`

**Interfaces:**
- Consumes: `DartToolchain.diagnose`, `ImportGraph`, `PackageMap`, `AnalyzeSettings`.
- Produces: `AnalyzeCheck implements Check` (`id: 'analyze'`, `hasDynamicRules: true`); `Future<Set<RepoPath>> analysisScope(CheckContext context, AnalyzeScope scope)`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('scope changed is the changed Dart files', () async { /* ... */ });
test('scope affected adds transitive importers from the same repository', () async { /* ... */ });
test('scope all is every Dart file of each touched package', () async { /* ... */ });
test('a changed pubspec.yaml or analysis_options.yaml widens that package to all', () async { /* ... */ });
test('deleted files are not requested, but their importers are', () async { /* ... */ });
test('severity mapping follows fail_on', () async {
  // fail_on: [error]; diagnostics: one error, one warning, one info
  expect(findings.map((f) => (f.rule.toString(), f.severity)), [('analyze/undefined_identifier', Severity.error), ('analyze/unused_import', Severity.warning)]);
});
test('info is reported only when listed in fail_on, then as an error', () async { /* ... */ });
test('the message and range are the analyzer\'s', () async { /* ... */ });
test('no changed Dart, pubspec or analysis_options file means the toolchain is never touched', () async {
  expect(context.dartAccessed, isFalse);
});
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/rules.md` `analyze`.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add analyze check on the affected scope`

### Task 11: The `sensitive-files` check

**Branch:** `feat/02-11-sensitive-files`

**Files:**
- Create: `lib/src/checks/sensitive_files/sensitive_files_check.dart`
- Test: `test/checks/sensitive_files/sensitive_files_check_test.dart`

**Interfaces:**
- Produces: `SensitiveFilesCheck implements Check` (`id: 'sensitive-files'`; rules `signing`, `credentials`).

- [ ] **Step 1: Write the failing tests.**

```dart
test('signing material by name and extension', () async {
  for (final p in ['android/key.properties', 'a/upload.jks', 'b.keystore', 'AuthKey_X.p8', 'cert.p12', 'c.pfx']) { /* one finding, 'Signing material must not be committed.' at 1:1 */ }
});
test('env files, except the documented examples', () async {
  for (final p in ['.env', '.env.production', 'app/.env.local']) { /* 'Credentials file must not be committed.' */ }
  for (final p in ['.env.example', '.env.sample', '.env.template', 'env.dart', '.envrc']) { /* nothing */ }
});
test('a service account JSON is detected by its type field', () async { /* {"type": "service_account", "private_key": "SECRET"} */ });
test('other JSON, JSON over 1 MiB and invalid JSON are not reported', () async { /* ... */ });
test('no finding message ever contains file content', () async {
  expect(findings.every((f) => !f.message.contains('SECRET')), isTrue);
});
test('deleted files are not reported; renamed files are, at the new path', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Extension matching is case-insensitive; basename matching is exact.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add sensitive-files check`

### Task 12: Pre-push entry point

**Branch:** `feat/02-12-pre-push`

**Files:**
- Create: `lib/src/application/hooks/pushed_refs.dart`
- Modify: `lib/src/infrastructure/git/git_cli_repository.dart`, `git_snapshot_files.dart` (commit snapshots), `lib/src/cli/commands/run_command.dart`
- Test: `test/application/hooks/pushed_refs_test.dart`, `test/infrastructure/git/pre_push_test.dart`, `test/acceptance/ac19_pre_push_test.dart`

**Interfaces:**
- Produces: `List<PushedRef> parsePushedRefs(String stdin)` throwing `UsageException`; `GitCliRepository.resolve(PrePushEntry)`; commit snapshots through `git ls-tree -r -z`; `Future<PushedRef?> synthesizeRef()` for manual runs.

- [ ] **Step 1: Write the failing tests.**

```dart
test('parses one ref per line and rejects malformed lines', () {
  expect(parsePushedRefs('refs/heads/f aaa refs/heads/f bbb\n').single.remoteRef, 'refs/heads/f');
  expect(() => parsePushedRefs('too few\n'), throwsA(isA<UsageException>()));
  expect(parsePushedRefs(''), isEmpty);
});
test('existing branch: base is the remote sha', () async { /* changeset = files changed since the pushed commit */ });
test('new branch: base is the merge-base with the remote\'s branches', () async {
  // origin has main and develop; feature was cut from develop with two commits
  expect(run.changes.changes.map((c) => c.path.value), ['only_in_feature.txt']);
});
test('first push of a repository: base is the empty tree', () async { /* every file added */ });
test('branch deletion and tag pushes produce no run', () async { expect(runs, isEmpty); });
test('a remote sha that is unknown locally falls back to the merge-base rule', () async { /* ... */ });
test('the snapshot is the pushed commit, not the index', () async { /* staged but uncommitted change is invisible */ });
test('two pushed branches produce two runs, in ref order', () async { /* ... */ });
test('without stdin, one ref is synthesized from the current branch and its upstream', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/git.md` section 4.2. `targetBranch` is the remote branch name. The console header reads `stagelatch pre-push <branch>`.
- [ ] **Step 4: Run** all four commands, including AC-19. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(cli): add run pre-push over pushed commits`

### Task 13: CI entry point

**Branch:** `feat/02-13-ci`

**Files:**
- Create: `lib/src/cli/commands/ci_command.dart`
- Modify: `lib/src/infrastructure/git/git_cli_repository.dart`, `lib/src/application/pipeline/selection.dart` (`hooks.ci` default)
- Test: `test/cli/ci_command_test.dart`, `test/infrastructure/git/ci_resolve_test.dart`, `test/acceptance/ac20_shallow_clone_test.dart`

**Interfaces:**
- Produces: `GitCliRepository.resolve(CiEntry)`; `List<HookSelector> selectorsFor(EntryKind kind, Config config, CheckCatalog catalog)`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('ci selectors default to the union of pre-commit and pre-push, pre-commit first, no duplicates', () { /* ... */ });
test('an explicit hooks.ci replaces the default', () { /* ... */ });
test('the changeset is merge-base(base, head)..head', () async { /* changes on base after the fork point are excluded */ });
test('--base is required', () async { expect(await run(['ci']), 64); });
test('ci never applies fixes', () async { /* unformatted file: exit 1, index unchanged */ });
test('a shallow clone without a merge base exits 64 with the fetch-depth message', () async {
  expect(err.toString(), contains('If this is a shallow clone, fetch full history (actions/checkout: fetch-depth: 0).'));
});
test('--reporter github prints workflow commands', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/git.md` section 4.3 and `specs/cli.md` section 3.5.
- [ ] **Step 4: Run** all four commands, including AC-20. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(cli): add ci command over the pull request diff`

### Task 14: `doctor`

**Branch:** `feat/02-14-doctor`

**Files:**
- Create: `lib/src/application/doctor/doctor.dart`, `probe_result.dart`, `lib/src/cli/commands/doctor_command.dart`
- Test: `test/application/doctor/doctor_test.dart`, `test/cli/doctor_command_test.dart`

**Interfaces:**
- Produces: `enum ProbeStatus { ok, warn, fail }`; `ProbeResult { String id; ProbeStatus status; String message }`; `Doctor(...)` with `Future<List<ProbeResult>> run()` returning D1–D9 in order.

- [ ] **Step 1: Write the failing tests,** one per row of the table in `specs/cli.md` section 3.6, with fakes, asserting id, status and message. Plus:

```dart
test('exit code is 1 when any probe fails, else 0', () async { /* ... */ });
test('console output is one line per probe prefixed by its status', () async { expect(lines.first, startsWith('ok    D1 ')); });
test('a probe that throws becomes a fail result and the others still run', () async { /* ... */ });
test('no environment variable value is printed', () async { /* S5 */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Each probe is one small function returning a `ProbeResult`.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(cli): add doctor command`

### Task 15: Wiring the toolchain into the pipeline

**Branch:** `feat/02-15-pipeline-toolchain`

**Files:**
- Modify: `lib/src/application/pipeline/pipeline.dart`, `pipeline_check_context.dart`, `lib/src/cli/composition.dart`, `lib/src/infrastructure/reporters/console_reporter.dart` (budget note)
- Test: `test/application/pipeline/toolchain_wiring_test.dart`, `test/acceptance/ac17_format_autofix_test.dart`, `ac18_overlay_test.dart`, `ac21_multi_package_test.dart`, `ac22_symlink_submodule_test.dart`

**Interfaces:**
- Consumes: `SdkLocator`, `DartToolchainFactory`, `buildPackageMap`, `ImportGraph`, `GitRepository.divergingFromWorktree`.
- Produces: `context.dart`, `context.packages` and `context.importGraph` are real; the toolchain is created on first access and closed in a `finally`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('the toolchain is not created when no check asks for it', () async { expect(factory.createCount, 0); });
test('overlays hold snapshot content for every diverging path and null for paths absent from the snapshot', () async { /* ... */ });
test('after the fix phase, overlays are recomputed for the reopened snapshot', () async { /* ... */ });
test('the toolchain is closed even when a check throws', () async { /* ... */ });
```

Acceptance:
  - AC-17: unformatted staged file: commit succeeds, committed blob is formatted; with unstaged edits the working tree is untouched; executable bit kept; `format.fix: false` blocks instead.
  - AC-18: staged file imports a file broken only in the working tree: exit 0. The reverse (broken in the index, fixed on disk): exit 1.
  - AC-21: two packages with different `analysis_options.yaml`; each file gets its own package's lints.
  - AC-22: a symlink and a submodule entry in the changeset: no crash, no content finding.
- [ ] **Step 2: Run.** Expected: FAIL, `UnsupportedError('Dart toolchain arrives in 0.1.0')`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(pipeline): wire the Dart toolchain with snapshot overlays`

### Task 16: Composite action and dogfooding

**Branch:** `ci/02-16-action-dogfood`

**Files:**
- Create: `action.yml`, `stagelatch.yaml`
- Modify: `.github/workflows/ci.yaml`

**Interfaces:**
- Produces: a composite action with inputs `base` (required), `version` (default: latest), `reporter` (default `github`) that activates stagelatch and runs `stagelatch ci`.

- [ ] **Step 1: Add `stagelatch.yaml`** for this repository: `hooks.pre-commit: [format, analyze, pubspec, sensitive-files]`, `hooks.pre-push: [analyze]`.
- [ ] **Step 2: Add a `dogfood` job** to CI on pull requests: `dart run bin/stagelatch.dart ci --base origin/${{ github.base_ref }} --reporter github`. It is a required check.
- [ ] **Step 3: Write `action.yml`.** Inputs are passed through `env:` and referenced as shell variables, never interpolated into the script text.
- [ ] **Step 4: Verify** by opening the pull request: the dogfood job runs and passes; introduce a deliberate formatting error in a scratch commit, see it fail with an annotation, then remove the commit.
- [ ] **Step 5: Commit.** `ci: add composite action and run stagelatch on itself`

### Task 17: Benchmark, demo and 0.1.0

**Branch:** `docs/02-17-release`

**Files:**
- Modify: `README.md`, `benchmark/README.md`, `docs/plans/README.md`
- Create: `docs/demo.tape`, `docs/demo.gif`

- [ ] **Step 1: Re-run the benchmark** of the spike with the real CLI on scenarios `s3` and `s10`, activated from path. Record p50 and p95.
- [ ] **Step 2: Write the README:** problem statement, a 60-second quick start, the rule table for this version, configuration summary, CI snippet, the benchmark table with the exact command to reproduce it, and the limitations (analyzer plugins, hooks are advisory).
- [ ] **Step 3: Record `demo.gif`** from `demo.tape` with VHS: a partially staged commit that is formatted in the index and then blocked by a path dependency.
- [ ] **Step 4: Verify** `dart pub publish --dry-run` is clean and all four commands pass.
- [ ] **Step 5: Commit.** `docs: add benchmark, demo and 0.1.0 README`
- [ ] **Step 6: Release** `0.1.0` per workflow section 8.

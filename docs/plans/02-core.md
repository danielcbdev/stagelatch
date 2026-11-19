# Core (0.1.0) Implementation Plan

Revised on 2026-11-19 after the spike (ADR-0008) and plan 01.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `0.1.0`: `format` with safe autofix, `analyze` on the affected scope over a materialized snapshot, `sensitive-files`, `run pre-push`, `ci`, `doctor`, JSON and GitHub reporters, SDK resolution, multi-package repositories and inline suppression.

**Architecture:** The Dart toolchain enters behind the `DartToolchain` port, implemented with the resolved SDK's analysis server for diagnostics and its `dart format --stdin-name` for formatting (ADR-0008). The pipeline gains the fix phase for real, an inline-ignore filter, and two more entry points that reuse the same use case with commit snapshots.

**Tech Stack:** As plan 01, plus `crypto`. No `analyzer` or `dart_style` dependency (ADR-0008).

**Spec:** [`specs/dart-toolchain.md`](../specs/dart-toolchain.md); [`specs/git.md`](../specs/git.md) 4.2, 4.3, 6; [`specs/cli.md`](../specs/cli.md) 3.4–3.6, 5, 6; [`specs/rules.md`](../specs/rules.md) `format`, `analyze`, `sensitive-files`, `stagelatch`; [`specs/baseline-and-suppression.md`](../specs/baseline-and-suppression.md) 1–3.

**Precondition:** met on 2026-11-19: `docs/spike/report.md` exists and ADR-0008 names the mechanism.

**Order.** Tasks 1 to 5, 8 and 11 are independent of each other. 6 needs 5; 7 needs 4, 5 and 6; 9 needs 7 and 8; 10 needs 6 and 7; 12 and 13 need 2 (reporter); 14 needs 4; 15 needs 4 to 11; 16 needs everything; 18 lands before the release step of 17. A task does not start while something in its Consumes is unmerged.

**`develop` stays releasable.** `format` and `analyze` are written in Tasks 9 and 10 but registered in `composition.dart` only in Task 15, together with the toolchain they need; until then `CheckContext.dart` still throws. `sensitive-files` needs no toolchain and is registered in Task 11.

## Global Constraints

- Everything in plan 01's Global Constraints.
- The analysis server protocol and the `dart format` invocation exist only under `lib/src/infrastructure/dart/`, and the tool imports neither `package:analyzer` nor `package:dart_style`. The layering test is extended to enforce both.
- `format` and `analyze` results equal those of the resolved SDK's `dart format` and `dart analyze` (ADR-0008). The contract tests of Task 7 are the proof and may not be weakened.
- The resolved SDK is outside the repository (S2).
- Fixes use only `hash-object -w`, `update-index --index-info` and `checkout-index` (S4).
- JSON output is byte-identical across runs once `durationMs` fields are removed.
- Every test that starts a process (the analysis server, `dart format`, the oracle's `dart analyze`) ends it in a `finally` or `addTearDown`. CI runs tests with `--concurrency=1` on Windows (PR #12), and a process left alive hangs the job.
- A task that removes an `arrives in 0.1.0` marker adjusts the test that pinned the marker in the same pull request.

## Review Focus

- **An unstaged edit in a file that a staged file imports.** Expected: the verdict ignores it. Pinned in Task 7 (contract test) and Task 15 (AC-18).
- **The first push of a repository, with no remote-tracking refs at all.** Expected: base is the empty tree and every file counts as added. Pinned in Task 12.
- **An analyzer message containing a newline or `::`.** Expected: the GitHub reporter escapes it so no extra workflow command is emitted. Pinned in Task 3.
- **A fix requested while `.git/index.lock` exists.** Expected: exit 70 naming the lock, index and working tree untouched. Pinned in Task 8.
- **A project that never ran `dart pub get`.** Expected: usage error with the command to run, only when Dart analysis is actually needed. Pinned in Task 7 and Task 15.
- **`git push` in a repository set up by `0.1.0-dev.1`.** The installed `pre-push` hook passes git's `<remote> <url>` arguments, which `run` rejects today with exit 64, so every push is blocked. Expected: `run pre-push origin <url>` is accepted. Pinned in Task 12.
- **A path that exists on disk but not in the snapshot** (an untracked file, or a deletion staged with `git rm --cached`). Expected: analysis never sees it, so its importers get `uri_does_not_exist`. Pinned in Task 7 and AC-18 (Task 15).
- **An unstaged change to `analysis_options.yaml`.** Expected: neither `format` nor `analyze` sees it. Pinned in Task 7.
- **Two verify checks asking for the toolchain at once.** Expected: one toolchain per run, one server per run at most. Pinned in Task 15.
- **A pushed commit that differs from the index.** Expected: the pushed commit is judged, and the materialized directory holds that commit's files. Pinned in Task 12 and Task 15.

---

### Task 1: Inline ignore filter

**Branch:** `feat/02-01-inline-ignore`

**Files:**
- Create: `lib/src/application/pipeline/inline_ignore.dart`
- Modify: `lib/src/application/pipeline/pipeline.dart` (call the filter; fill `RunReport.suppressed`, today hard-coded to 0)
- Test: `test/application/pipeline/inline_ignore_test.dart`, `test/application/pipeline/pipeline_test.dart`

**Interfaces:**
- Consumes: `Finding`, `SnapshotFiles`, `ChangeSet`, `CheckCatalog`.
- Produces: `List<IgnoreDirective> scanIgnores(String text, {required String commentOpener})`; `IgnoreDirective { int line; List<IgnoreId> ids }`; `IgnoreId { String text; int column }`; `String? commentOpenerFor(RepoPath path)` returning `//`, `#` or null; `Future<IgnoreOutcome> applyInlineIgnores(List<Finding> findings, {required SnapshotFiles snapshot, required ChangeSet changes, required CheckCatalog catalog})`; `IgnoreOutcome { List<Finding> kept; int suppressed; List<Finding> invalid }`.

- [x] **Step 1: Write the failing tests.**

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
test('the pipeline drops covered findings and reports how many', () async {
  expect(report.suppressed, 1); expect(report.findings, isEmpty);
});
```

- [x] **Step 2: Run.** Expected: FAIL, `scanIgnores` undefined.
- [x] **Step 3: Implement** with a hand-written scan per line (`indexOf` of the opener, then the marker); no regular expression. Insert the filter in the chain after `exclude` and before the baseline position (`specs/baseline-and-suppression.md` section 1). It reads the snapshot as the fix phase left it. `invalid-ignore` findings bypass inline suppression but still go through the levels filter, so `rules: {stagelatch/invalid-ignore: off}` silences them. `RunRequest`, `RunReport` and the console reporter need no change: `suppressed` already exists and is printed.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(pipeline): add inline stagelatch:ignore suppression`

### Task 2: JSON reporter

**Branch:** `feat/02-02-json-reporter`

**Files:**
- Create: `lib/src/infrastructure/reporters/json_reporter.dart`, `test/goldens/json/single.json`, `test/goldens/json/multi.json`
- Modify: `lib/src/cli/commands/run_command.dart` (`--reporter` accepts `json`; today anything but `console` is a usage error, PR #13), `lib/src/cli/runner.dart` (error object), `test/acceptance/determinism_test.dart` (to the form of `testing.md` section 5, first half)
- Test: `test/infrastructure/reporters/json_reporter_test.dart`, `test/cli/reporter_option_test.dart`

**Interfaces:**
- Consumes: `Reporter`, `RunReport`, `AppliedFix`, `CheckTiming` (plan 01).
- Produces: `JsonReporter(StringSink out, {required String toolVersion}) implements Reporter`; `String renderErrorJson({required String kind, required String message, required int exitCode})`.

- [x] **Step 1: Write the failing tests.**

```dart
test('one run renders the object of specs/cli.md section 5, keys in order', () { /* golden: single.json */ });
test('several runs render a "runs" array with a top-level verdict and exit code', () { /* golden: multi.json */ });
test('output is identical across runs after removing durationMs', () { /* two reports differing only in durations */ });
test('exit 64, 70 and 78 print the error object on stdout and the message on stderr', () async {
  expect(out.toString(), '{"schemaVersion":1,"error":{"kind":"usage","message":"Unknown hook \\"x\\"."},"exitCode":64}\n');
});
test('strings are encoded by the JSON encoder, never concatenated', () { /* message with quotes, backslash, newline */ });
test('--reporter github on run is a usage error naming the accepted values', () async {
  expect(err.toString(), contains('Unknown reporter "github". Expected console or json.'));
});
// test/acceptance/determinism_test.dart, rewritten:
test('two runs with --reporter json are byte-identical once durationMs is removed', () async {
  expect(withoutDurations(first.stdout), withoutDurations(second.stdout));
  expect(jsonDecode(first.stdout)['verdict'], 'fail');
});
```

The shuffled-registry half of the determinism test needs several registered checks and arrives in Task 15.

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement** with `JsonEncoder.withIndent('  ')` over a `LinkedHashMap` built in the documented key order (`specs/cli.md` section 5); the error object is rendered compact. `--all` stays the usage error `--all arrives in 0.2.0.`
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(reporters): add JSON reporter`

### Task 3: GitHub reporter

**Branch:** `feat/02-03-github-reporter`

**Files:**
- Create: `lib/src/infrastructure/reporters/github_reporter.dart`
- Test: `test/infrastructure/reporters/github_reporter_test.dart`

**Interfaces:**
- Consumes: `Reporter`, `RunReport`, `sanitizeForTerminal`, `counted` and `formatSeconds` (`console_format.dart`, plan 01).
- Produces: `String escapeWorkflowData(String)`; `String escapeWorkflowProperty(String)`; `GithubReporter(StringSink out) implements Reporter`; `String summaryLine(RunReport report)` moved out of `ConsoleReporter` into `console_format.dart` so both reporters print the same line. Only `ci` offers `--reporter github` (Task 13).

- [x] **Step 1: Write the failing tests.**

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

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement.** Paths containing `,` or `:` go through `escapeWorkflowProperty`.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(reporters): add GitHub workflow command reporter`

### Task 4: SDK locator

**Branch:** `feat/02-04-sdk-locator`

**Files:**
- Create: `lib/src/application/ports/sdk_locator.dart`, `lib/src/infrastructure/dart/file_sdk_locator.dart`, `test/support/fake_sdk_locator.dart`
- Test: `test/infrastructure/dart/file_sdk_locator_test.dart`

**Interfaces:**
- Consumes: `Config.sdkPath`, `Environment` (`variables` for `PATH`, `HOME`, `FVM_CACHE_PATH`), `RepoLayout.root` (plan 01).
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
- Test: `test/application/packages/package_map_builder_test.dart`

**Interfaces:**
- Consumes: `DartPackage { RepoPath? root; String name; bool usesFlutter }` (a null root is the repository root), `PackageMap` and `PackageMap.packageOf`, all in `lib/src/domain/package_map.dart` and tested since plan 01; `SnapshotFiles`; `Documents`.
- Produces: `Future<PackageMap> buildPackageMap(SnapshotFiles snapshot, Documents documents)`.

- [x] **Step 1: Write the failing tests.**

```dart
test('a file belongs to the nearest enclosing pubspec', () async {
  final map = await buildPackageMap(FakeSnapshotFiles({'pubspec.yaml': 'name: app\n', 'packages/ui/pubspec.yaml': 'name: ui\n', 'packages/ui/lib/a.dart': '', 'lib/b.dart': ''}), docs);
  expect(map.packageOf(RepoPath('packages/ui/lib/a.dart'))!.name, 'ui');
  expect(map.packageOf(RepoPath('lib/b.dart'))!.name, 'app');
});
test('a file outside every package has none', () async { /* no root pubspec */ });
test('usesFlutter is read from an sdk: flutter dependency', () async { /* ... */ });
test('an unparseable pubspec, or one without a string name, still defines a package with an empty name', () async {
  expect(map.packageOf(RepoPath('tool/x.dart')), const DartPackage(root: RepoPath('tool'), name: ''));
});
test('packages are sorted by root', () async { /* ... */ });
```

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement** per `specs/dart-toolchain.md` section 2: list the snapshot once, keep every path whose basename is `pubspec.yaml`, parse each through `Documents.yaml`. The lookup itself is `PackageMap.packageOf` and does not change.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(packages): map files to their nearest pubspec`

### Task 6: Directive facts and the import graph

**Branch:** `feat/02-06-import-graph`

**Files:**
- Create: `lib/src/domain/dart/import_graph.dart`, `lib/src/infrastructure/dart/syntactic_facts.dart`
- Modify: `lib/src/domain/check.dart` (add `Future<ImportGraph> get importGraph` to `CheckContext`), `test/support/fake_check_context.dart` (a graph given at construction, default empty), `lib/src/application/pipeline/pipeline_check_context.dart` (the getter throws the same `UnsupportedError('The Dart toolchain arrives in 0.1.0.')` as `dart` until Task 15)
- Test: `test/domain/dart/import_graph_test.dart`, `test/infrastructure/dart/syntactic_facts_test.dart`

**Interfaces:**
- Consumes: `Directive`, `DirectiveKind`, `DartFileFacts` (`lib/src/domain/dart/dart_file_facts.dart`, since plan 01), `PackageMap`.
- Produces: `ImportGraph.build({required Map<RepoPath, List<Directive>> directives, required PackageMap packages})`; `Set<RepoPath> dependentsOf(Set<RepoPath> files)`; `List<RepoPath>? shortestChain(RepoPath from, RepoPath to)`; `const SyntacticFacts()` with `DartFileFacts extract(String source, RepoPath path)`, filling `directives` only in this version (`specs/dart-toolchain.md` section 6). The `tests.functions` parameter arrives with `testCalls` in plan 03.

- [x] **Step 1: Write the failing tests.**

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
test('extract returns each directive with the location of its URI literal', () {
  final d = const SyntacticFacts().extract("import 'b.dart';\n", RepoPath('lib/a.dart')).directives.single;
  expect((d.kind, d.uri), (DirectiveKind.import, 'b.dart'));
  expect(d.location, Location(RepoPath('lib/a.dart'), const Position(1, 8), const Position(1, 16)));
});
test('scanning stops at the first token that does not start a directive', () {
  // "import 'a.dart';\nvoid main() {}\nimport 'late.dart';" -> only a.dart
});
test('a syntax error after the directives does not hide them', () { /* "import 'a.dart';\nclass {" -> a.dart */ });
test('library, annotations, a script tag and part of with a library name produce no URI', () { /* ... */ });
test('directive-like text in comments and strings is ignored', () { /* "// import 'x.dart';" */ });
test('adjacent string literals are concatenated', () { /* "import 'a' '.dart';" -> a.dart */ });
```

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement.** `SyntacticFacts` is the hand-written directive scanner selected by the spike (ADR-0008; `benchmark/lib/directives_scan.dart` is the measured prototype): it skips comments, strings and raw strings, and yields each `import`, `export`, `part` and `part of` with its URI and location, one per conditional branch. The graph stores reverse adjacency in sorted sets.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(dart): add directive facts and import graph`

### Task 7: Dart toolchain adapter

**Branch:** `feat/02-07-dart-toolchain`

**Files:**
- Create: `lib/src/application/ports/dart_toolchain_factory.dart`, `test/support/fake_dart_toolchain.dart`, `test/support/fake_dart_toolchain_factory.dart`
- Create: `lib/src/infrastructure/dart/analysis_server_client.dart` (JSON-RPC over the server's stdin and stdout), `lib/src/infrastructure/dart/materialized_snapshot.dart` (writes the snapshot's Dart and YAML files, or only its settings files, and the package configs into a temp directory), `lib/src/infrastructure/dart/sdk_dart_toolchain.dart` (the adapter: diagnostics through the server on the materialized snapshot, formatting through `dart format --stdin-name`)
- Create: `test/fixtures/dart_app/` (a dependency-free Dart package: `pubspec.yaml`, `analysis_options.yaml` with `formatter: page_width: 100` and two built-in lint rules, `lib/`), `test/support/oracle.dart`, `test/support/fixture_package.dart` (copies the fixture into a temp directory and runs the SDK's `dart pub get --offline`, which needs no network for a package without dependencies)
- Modify: `lib/src/domain/dart/dart_toolchain.dart` (the port's doc comment names the mechanism instead of "chosen by the spike"; `facts` returns null only for an absent or non-text file)
- Modify: `test/architecture/layering_test.dart` (no `package:analyzer` or `package:dart_style` anywhere; the server protocol only under `infrastructure/dart/`)
- Test: `test/infrastructure/dart/toolchain_contract_test.dart`, `test/infrastructure/dart/materialized_snapshot_test.dart`

**Interfaces:**
- Consumes: `ResolvedSdk` (Task 4), `SyntacticFacts` (Task 6), `PackageMap`, `SnapshotFiles`, and the `DartToolchain` port with `diagnose`, `format`, `facts` and `close` (`lib/src/domain/dart/dart_toolchain.dart`, since plan 01; `close` already exists).
- Produces: `DartToolchainFactory { DartToolchain create({required ResolvedSdk sdk, required String repoRoot, required SnapshotFiles snapshot, required PackageMap packages}) }`, synchronous because creating starts no process and writes no file. `SdkDartToolchainFactory implements DartToolchainFactory` and `SdkDartToolchain implements DartToolchain` in `sdk_dart_toolchain.dart`; `MaterializedSnapshot` (`static Future<MaterializedSnapshot> write({required SnapshotFiles snapshot, required String repoRoot, required Iterable<DartPackage> packages, bool settingsOnly = false})`, `String get root`, `String pathOf(RepoPath path)`, `RepoPath? repoPathOf(String absolutePath)`, `Future<void> delete()`); `AnalysisServerClient` (`static Future<AnalysisServerClient> start(String dartExecutable)`, `Future<Map<String, Object?>> request(String method, Map<String, Object?> params)`, `Future<void> close()`). In test support: `FakeDartToolchain` recording `diagnose`, `format` and `facts` calls with canned answers; `FakeDartToolchainFactory` counting `create` calls and recording the snapshot each was given; `Future<OracleResult> runOracle(String packageDir)`, which runs the SDK's `dart analyze --format=json` and `dart format --output=json` on a directory, as the spike's oracle does (`benchmark/lib/oracle.dart`).

- [ ] **Step 1: Write the failing tests.** The contract tests never mention the mechanism. The snapshot is a `FakeSnapshotFiles`; the working tree is a fixture copy on disk whose files may differ from it.

```dart
test('diagnostics equal dart analyze on a tree identical to the snapshot', () async {
  // fixture gets one error, one warning, one lint; snapshot == disk
  expect(await toolchain.diagnose(files), equalsOracle(await runOracle(fixture)));
});
test('the snapshot content wins over the file on disk', () async {
  // disk: lib/a.dart has an error; snapshot: clean content
  expect(await toolchain.diagnose({RepoPath('lib/a.dart')}), isEmpty);
});
test('an unstaged error in an imported file does not leak', () async {
  // disk: lib/dep.dart broken; snapshot: lib/dep.dart valid
  expect(await toolchain.diagnose({RepoPath('lib/uses_dep.dart')}), isEmpty);
});
test('a file on disk that is absent from the snapshot is invisible', () async {
  // disk: lib/gone.dart exists (untracked, or deleted only in the index); snapshot: no lib/gone.dart
  expect((await toolchain.diagnose({RepoPath('lib/uses_gone.dart')})).single.code, 'uri_does_not_exist');
});
test('only requested files are reported', () async { /* ... */ });
test('ignore comments and analysis_options are honored', () async { /* ... */ });
test('locations and messages name repository paths, never the temporary directory', () async { /* ... */ });
test('format equals dart format, including page_width from analysis_options', () async {
  expect(((await toolchain.format(path, source)) as Formatted).text, (await runOracle(fixture)).formatted[path.value]);
});
test('format keeps CRLF when the input uses CRLF', () async { /* ... */ });
test('format of unparseable source is Unparseable', () async { /* exit 65 */ });
test('format and facts start no analysis server', () async { /* ... */ });
test('an unstaged page_width change does not change the formatted text', () async { /* ... */ });
test('a package without .dart_tool/package_config.json is a usage error', () async {
  expect(e.message, 'Missing .dart_tool/package_config.json. Run: dart pub get');
});
test('close ends every child process and removes every directory it wrote', () async { /* ... */ });
// materialized_snapshot_test.dart
test('writes regular and executable .dart, .yaml and .yml files byte for byte, and nothing else', () async { /* symlink, gitlink, .png skipped */ });
test('package config roots inside the repository stay relative; others become absolute', () async { /* ... */ });
test('paths with spaces and non-ASCII characters round-trip through pathOf and repoPathOf', () async { /* ... */ });
```

The contract tests use the `dart` on `PATH` as the resolved SDK, through `FileSdkLocator`, so they run on stable and on beta in CI. Each test closes its toolchain in `addTearDown`.

- [ ] **Step 2: Run** `dart test test/infrastructure/dart/`. Expected: FAIL, no adapter.
- [ ] **Step 3: Implement** the mechanism of ADR-0008 per `specs/dart-toolchain.md` sections 4, 5, 7 and 8. On the first `diagnose`, write the materialized snapshot (from `SnapshotFiles.readBytes`, so no git command is added), then start the server; never for `format` or `facts`. `format` runs `dart format --output=show --stdin-name=<path of the file inside the settings directory>` with the source on stdin; the settings directory is written on the first `format` and holds only the snapshot's `pubspec.yaml` and `analysis_options.yaml` files and the package configs, so `page_width` and the language version come from the snapshot (`specs/dart-toolchain.md` section 5). `close()` shuts the server down, kills it after 5 s, and deletes the directory. Every protocol call has a comment saying what it does and why that call was chosen; `benchmark/lib/server_client.dart`, `benchmark/lib/probe_delegated.dart` and `benchmark/lib/oracle.dart` (`_copyPackageConfig`) are the measured prototypes.
  - Pin it with a contract test: an unstaged `page_width` change in `analysis_options.yaml` does not change the formatted text.
- [ ] **Step 4: Run** all four commands on all matrix cells. Expected: PASS. A contract test that fails on one OS or on Dart beta is a blocker, not a skip.
- [ ] **Step 5: Commit.** `feat(dart): add toolchain adapter over a materialized snapshot`

### Task 8: Applying fixes to the index

**Branch:** `feat/02-08-apply-fixes`

**Files:**
- Modify: `lib/src/infrastructure/git/git_cli_repository.dart` (`applyFixes`, which today throws `UnsupportedError('Fixes arrive in 0.1.0.')`), `test/infrastructure/git/git_cli_repository_test.dart` (drop the test `fixes arrive in 0.1.0`)
- Test: `test/infrastructure/git/apply_fixes_test.dart`

`run --no-fix` already exists (plan 01) and needs no change: the pipeline applies fixes only when `RunRequest.allowFixes` is true and the snapshot is the index.

**Interfaces:**
- Consumes: `Fix`, `AppliedFix`, the `GitRepository.applyFixes` port (plan 01).
- Produces: `GitCliRepository.applyFixes(List<Fix> fixes) -> Future<List<AppliedFix>>` for the index; afterwards `files(IndexSnapshot())` returns a view of the updated index.

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
test('the index view is refreshed after fixes', () async { expect(await git.files(const IndexSnapshot()).readText(RepoPath('a.dart')), 'fixed\n'); });
```

- [ ] **Step 2: Run.** Expected: FAIL, `applyFixes` throws `UnsupportedError`.
- [ ] **Step 3: Implement** the four steps of `specs/git.md` section 6, in that order, through `GitProcess` only (S4: `diff`, `hash-object -w --stdin --no-filters`, `update-index -z --index-info`, `checkout-index --force --`). A held `index.lock` makes step 3 fail; map that failure to `InternalException` whose message names `index.lock`, before step 4 runs.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(git): apply fixes through the index without touching unstaged work`

### Task 9: The `format` check

**Branch:** `feat/02-09-format-check`

**Files:**
- Create: `lib/src/checks/format/format_check.dart`, `first_difference.dart`
- Test: `test/checks/format/format_check_test.dart`, `first_difference_test.dart`

The pipeline already applies a fix only for a finding that survived the filters, so an excluded path or a rule turned off is never fixed (plan 01, `pipeline.dart`). The check is registered in Task 15, with the toolchain.

**Interfaces:**
- Consumes: `DartToolchain.format`, `FormatSettings` (`lib/src/application/config/settings.dart`, plan 01), `FakeDartToolchain` (Task 7), `FakeCheckContext`.
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
test('the fix is returned whatever the entry; the pipeline decides whether to apply it', () async { /* entry prePush: one finding, one fix */ });
test('format.fix false returns the finding without a fix', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/rules.md` `format`. Files are formatted concurrently and results consumed in path order. Only changed `.dart` files that are regular or executable and readable as text are formatted.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add format check with index autofix`

### Task 10: The `analyze` check

**Branch:** `feat/02-10-analyze-check`

**Files:**
- Create: `lib/src/checks/analyze/analyze_check.dart`, `analysis_scope.dart`
- Modify: `lib/src/application/config/default_hooks.dart` (`analyze` leaves the `pre-commit` default and stays in `pre-push`, so also in `ci`; ADR-0008), `test/application/config/default_hooks_test.dart`
- Test: `test/checks/analyze/analysis_scope_test.dart`, `analyze_check_test.dart`

**Interfaces:**
- Consumes: `DartToolchain.diagnose`, `ImportGraph` and `CheckContext.importGraph` (Task 6), `PackageMap`, `AnalyzeSettings` and `AnalyzeScope` (`settings.dart`, plan 01), `FakeDartToolchain` (Task 7).
- Produces: `AnalyzeCheck implements Check` (`id: 'analyze'`, `phase: CheckPhase.verify`, `hasDynamicRules: true`); `Future<Set<RepoPath>> analysisScope(CheckContext context, AnalyzeScope scope)`.

The check is registered in Task 15, with the toolchain.

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
// default_hooks_test.dart
test('analyze is on pre-push and ci by default, not on pre-commit', () {
  expect(defaults(preCommitHook, catalog), isNot(contains('analyze')));
  expect(defaults(prePushHook, catalog), ['analyze', 'tests/affected']);
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
- Modify: `lib/src/cli/composition.dart` (register after `PubspecCheck`), `test/cli/runner_test.dart` (`init` now writes `pre-commit: [pubspec, sensitive-files]`)
- Test: `test/checks/sensitive_files/sensitive_files_check_test.dart`

**Interfaces:**
- Consumes: `CheckContext.changes`, `snapshot` and `documents` (JSON).
- Produces: `SensitiveFilesCheck implements Check` (`id: 'sensitive-files'`, `phase: CheckPhase.verify`; rules `signing`, `credentials`).

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
- [ ] **Step 3: Implement** per `specs/rules.md` `sensitive-files`. Extension matching is case-insensitive; basename matching is exact. JSON is read only when `SnapshotFiles.size` is at most 1 MiB, then parsed through `Documents.json`.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add sensitive-files check`

### Task 12: Pre-push entry point

**Branch:** `feat/02-12-pre-push`

**Files:**
- Create: `lib/src/application/hooks/pushed_refs.dart`
- Modify: `lib/src/infrastructure/git/git_cli_repository.dart` (`resolve(PrePushEntry)`; today `PrePushEntry` and `CiEntry` share `UnsupportedError('This entry point arrives in 0.1.0.')`), `lib/src/cli/commands/run_command.dart` (drop `UsageException('pre-push arrives in 0.1.0.')`; accept git's `<remote> <url>`; read stdin), `test/infrastructure/git/git_cli_repository_test.dart` (the `pre-push and ci entries arrive in 0.1.0` test keeps only the `ci` half)
- Test: `test/application/hooks/pushed_refs_test.dart`, `test/infrastructure/git/pre_push_test.dart`, `test/cli/run_pre_push_test.dart`, `test/acceptance/ac19_pre_push_test.dart`

Commit snapshots are already read through `git ls-tree -r -z` (plan 01, `git_snapshot_files.dart`), and the console header `pre-push <branch>` and the `Push blocked`/`Push allowed` outcome already exist (`console_reporter.dart`).

**Interfaces:**
- Consumes: `PrePushEntry`, `PushedRef` (`entry_point.dart`, plan 01), `CommitSnapshot`, `ResolvedRun`, `Environment.stdinIsTerminal`.
- Produces: `List<PushedRef> parsePushedRefs(String stdin)` throwing `UsageException`; `GitCliRepository.resolve(PrePushEntry)`; `Future<PrePushEntry> GitCliRepository.synthesizePrePush({String? remote})` for manual runs, where `GitCliRepository` gains it as a `GitRepository` port method with the same signature.

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
test('without stdin, no upstream and no remote argument, the remote is origin', () async { /* specs/cli.md 3.4 */ });
// run_pre_push_test.dart
test('the hook arguments <remote> <url> are accepted, with or without --', () async {
  expect((await run(['run', 'pre-push', 'origin', 'https://example.invalid/r.git'], stdin: line)).exitCode, 0);
  expect((await run(['run', 'pre-push', '--', 'origin', 'u'], stdin: line)).exitCode, 0);
});
test('one extra argument is the unknown-hook usage error', () async {
  expect(err.toString(), contains('Unknown hook "pre-push origin". Expected pre-commit or pre-push.'));
});
test('the pre-push hook installed by init lets a real git push through', () async { /* push to a bare remote in a temp dir: exit 0 */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/git.md` section 4.2 and `specs/cli.md` section 3.4. `targetBranch` and `label` are the remote branch name. Stdin is read to its end only when `Environment.stdinIsTerminal` is false; empty input then means a manual run.
- [ ] **Step 4: Run** all four commands, including AC-19. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(cli): add run pre-push over pushed commits`. The pull request description calls out the `0.1.0-dev.1` bug it fixes: every `git push` in a repository set up by `init` was blocked with exit 64.

### Task 13: CI entry point

**Branch:** `feat/02-13-ci`

**Files:**
- Create: `lib/src/cli/commands/ci_command.dart`
- Modify: `lib/src/infrastructure/git/git_cli_repository.dart` (`resolve(CiEntry)`), `lib/src/cli/runner.dart` (register `ci`), `test/infrastructure/git/git_cli_repository_test.dart` (drop the rest of `pre-push and ci entries arrive in 0.1.0`)
- Test: `test/cli/ci_command_test.dart`, `test/infrastructure/git/ci_resolve_test.dart`, `test/acceptance/ac20_shallow_clone_test.dart`

The `hooks.ci` default already exists: `ConfigLoader` fills `ci` with `unionOfSelectors(preCommit, prePush)` when the key is absent, and `Pipeline` reads `config.hooks['ci']` for `EntryKind.ci` (plan 01). This task adds no selection code.

**Interfaces:**
- Consumes: `CiEntry`, `unionOfSelectors` and `ciHook` (`default_hooks.dart`), `JsonReporter` (Task 2), `GithubReporter` (Task 3).
- Produces: `GitCliRepository.resolve(CiEntry)`; `CiCommand`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('without hooks.ci, ci runs the union of pre-commit and pre-push', () async { /* end to end: a sensitive file and an analyze finding both reported */ });
test('the changeset is merge-base(base, head)..head', () async { /* changes on base after the fork point are excluded */ });
test('--base is required', () async { expect(await run(['ci']), 64); });
test('ci never applies fixes', () async { /* unformatted file: exit 1, index unchanged */ });
test('a shallow clone without a merge base exits 64 with the fetch-depth message', () async {
  expect(err.toString(), contains('If this is a shallow clone, fetch full history (actions/checkout: fetch-depth: 0).'));
});
test('--reporter github prints workflow commands', () async { /* ... */ });
test('an unknown reporter is a usage error naming the accepted values', () async {
  expect(err.toString(), contains('Unknown reporter "sarif". Expected console, json or github.'));
});
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/git.md` section 4.3 and `specs/cli.md` section 3.5.
- [ ] **Step 4: Run** all four commands, including AC-20. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(cli): add ci command over the pull request diff`

### Task 14: `doctor`

**Branch:** `feat/02-14-doctor`

**Files:**
- Create: `lib/src/application/doctor/doctor.dart`, `probe_result.dart`, `lib/src/application/ports/doctor_probes.dart`, `lib/src/infrastructure/io/local_doctor_probes.dart`, `lib/src/cli/commands/doctor_command.dart`
- Modify: `lib/src/cli/runner.dart` (register `doctor`)
- Test: `test/application/doctor/doctor_test.dart`, `test/cli/doctor_command_test.dart`

**Interfaces:**
- Consumes: `SdkLocator` (Task 4), `GitRepository.layout`, `HookStore`, `ConfigLoader`, `buildPackageMap` (Task 5), `Environment`.
- Produces: `enum ProbeStatus { ok, warn, fail }`; `ProbeResult { String id; ProbeStatus status; String message }`; `Doctor({required GitRepository git, required HookStore hooks, required ConfigLoader loader, required SdkLocator sdk, required Environment environment, required DoctorProbes probes})` with `Future<List<ProbeResult>> run()` returning D1–D9 in order; `DoctorProbes`, a port in `lib/src/application/ports/doctor_probes.dart` for what only infrastructure can see (`Future<String?> gitVersion()`, `Future<String?> resolveOnPath(String name)`, `Future<bool> exists(String repoRelativePath)`), with `LocalDoctorProbes` in `lib/src/infrastructure/io/local_doctor_probes.dart`.

- [ ] **Step 1: Write the failing tests,** one per cell of the message table in `specs/cli.md` section 3.6, with fakes, asserting id, status and the exact message. Plus:

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
- Modify: `lib/src/application/pipeline/pipeline.dart`, `pipeline_check_context.dart` (drop `UnsupportedError('The Dart toolchain arrives in 0.1.0.')` from `dart` and `importGraph`), `lib/src/cli/composition.dart` (register `FormatCheck` and `AnalyzeCheck`; wire `FileSdkLocator` and `SdkDartToolchainFactory`; an optional `checks` parameter of `Composition.create` for tests), `test/application/pipeline/pipeline_test.dart` (the test `has no Dart toolchain before 0.1.0` becomes `creates no toolchain when no check asks for it`), `test/cli/runner_test.dart` (`init` expectations), `test/acceptance/determinism_test.dart` (second half of `testing.md` section 5)
- Test: `test/application/pipeline/toolchain_wiring_test.dart`, `test/acceptance/ac17_format_autofix_test.dart`, `ac18_snapshot_isolation_test.dart`, `ac21_multi_package_test.dart`, `ac22_symlink_submodule_test.dart`

The console budget note already exists (`console_reporter.dart`, plan 01) and needs no change.

**Interfaces:**
- Consumes: `SdkLocator` (Task 4), `buildPackageMap` (Task 5), `ImportGraph` and `SyntacticFacts` through `DartToolchain.facts` (Task 6), `DartToolchainFactory` and `FakeDartToolchainFactory` (Task 7), `FormatCheck` (Task 9), `AnalyzeCheck` (Task 10).
- Produces: `Pipeline` gains `required SdkLocator sdkLocator` and `required DartToolchainFactory toolchains`; `context.dart`, `context.packages` and `context.importGraph` are real. Production registry order: `FormatCheck`, `AnalyzeCheck`, `PubspecCheck`, `SensitiveFilesCheck`, the order of the documented hook lists.

- [ ] **Step 1: Write the failing tests.**

```dart
test('the toolchain is not created when no check asks for it', () async { expect(factory.createCount, 0); });
test('the SDK is not located when no check asks for the toolchain', () async { expect(locator.calls, 0); });
test('concurrent verify checks share one toolchain', () async { expect(factory.createCount, 1); });
test('the fix phase and the verify phase get separate toolchains, the second over the fixed index', () async {
  expect(factory.snapshots.last.readText(path), completion('fixed\n'));
});
test('every toolchain is closed, even when a check throws', () async { /* ... */ });
test('packages come from the snapshot, and the import graph from facts of every .dart file', () async { /* ... */ });
// determinism_test.dart, second half
test('a reversed check registry gives byte-identical JSON once durationMs is removed', () async {
  // scenario: pubspec path dependency, .env file, unformatted lib file; run pre-commit --no-fix --reporter json
});
// runner_test.dart
test('init in a Dart repository writes pre-commit and pre-push and installs both hooks', () async {
  expect(await repo.read('stagelatch.yaml'), contains('pre-commit: [format, pubspec, sensitive-files]\n  pre-push: [analyze]\n'));
  expect(result.stdout, contains('Installed pre-commit hook at ')); expect(result.stdout, contains('Installed pre-push hook at '));
});
```

Acceptance:
  - AC-17: unformatted staged file: commit succeeds, committed blob is formatted; with unstaged edits the working tree is untouched; executable bit kept; `format.fix: false` blocks instead.
  - AC-18: a staged file imports a file broken only in the working tree: exit 0. The reverse (broken in the index, fixed on disk): exit 1. A staged file imports an untracked file: exit 1 with `analyze/uri_does_not_exist`. A file removed with `git rm --cached` but still on disk, imported by a staged file: exit 1.
  - AC-21: two packages with different `analysis_options.yaml`; each file gets its own package's lints.
  - AC-22: a symlink and a submodule entry in the changeset: no crash, no content finding.
- [ ] **Step 2: Run.** Expected: FAIL, `UnsupportedError('The Dart toolchain arrives in 0.1.0.')`.
- [ ] **Step 3: Implement.** One lazily created toolchain per phase, memoized in the phase's context so concurrent checks share it, all closed in a `finally` around the run. The SDK is located on the first `dart` access, not before. `importGraph` is memoized per context and built from `dart.facts` of every `.dart` file of the snapshot (`facts` starts no process). Acceptance tests that need `analyze` run `dart pub get --offline` in their temp repository first.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(pipeline): wire the Dart toolchain over a materialized snapshot`

### Task 16: Composite action and dogfooding

**Branch:** `ci/02-16-action-dogfood`

**Files:**
- Create: `action.yml`, `stagelatch.yaml`
- Modify: `.github/workflows/ci.yaml`

**Interfaces:**
- Consumes: `stagelatch ci` (Task 13) with every check registered (Task 15).
- Produces: a composite action with inputs `base` (required), `version` (default: latest), `reporter` (default `github`) that activates stagelatch and runs `stagelatch ci`.

- [ ] **Step 1: Add `stagelatch.yaml`** for this repository: `hooks.pre-commit: [format, pubspec, sensitive-files]`, `hooks.pre-push: [analyze]`, the defaults of ADR-0008.
- [ ] **Step 2: Add a `dogfood` job** to CI on pull requests: checkout with `fetch-depth: 0`, `dart pub get`, then `dart run bin/stagelatch.dart ci --base "origin/$BASE_REF" --reporter github`, with `BASE_REF: ${{ github.base_ref }}` under `env:`. `permissions: contents: read`.
- [ ] **Step 3: Write `action.yml`.** Inputs are passed through `env:` and referenced as shell variables, never interpolated into the script text (S8). Third-party actions pinned by SHA.
- [ ] **Step 4: Verify** by opening the pull request: the dogfood job runs and passes; introduce a deliberate formatting error in a scratch commit, see it fail with an annotation, then remove the commit.
- [ ] **Step 5: Commit.** `ci: add composite action and run stagelatch on itself`. Making `dogfood` a required check is branch protection, an owner action: the pull request description asks for it and nothing here changes repository settings.

### Task 17: Benchmark, demo and 0.1.0

**Branch:** `docs/02-17-release`, then `release/0.1.0` for the release pull request.

**Files:**
- Modify: `README.md`, `benchmark/README.md`, `docs/plans/README.md` (plan 02: `done (0.1.0)`), `docs/plans/02-core.md` (this task's last step ticked)
- Create: `docs/demo.tape`, `docs/demo.gif`

**Interfaces:**
- Consumes: everything above; Task 18 merged before Step 6.

- [ ] **Step 1: Re-run the benchmark** of the spike with the real CLI on scenarios `s3` and `s10`, activated with `dart pub global activate --source path .`, cold (fresh temporary caches) and warm. Record p50 and p95 of `run pre-commit` (default lists: no `analyze`) and of `run pre-push` (`analyze`). **Stop and ask the owner** if `pre-commit` p50 is clearly above 2 s.
- [ ] **Step 2: Write the README:** problem statement, a 60-second quick start, the rule table for this version, configuration summary, CI snippet, the benchmark table with the exact command to reproduce it, and the limitations (analyzer plugins, hooks are advisory, `analyze` costs one analysis server start per run and runs on push by default).
- [ ] **Step 3: Record `demo.gif`** from `demo.tape` with VHS: a partially staged commit that is formatted in the index and then blocked by a path dependency.
- [ ] **Step 4: Verify** `dart pub publish --dry-run` is clean and all four commands pass.
- [ ] **Step 5: Commit.** `docs: add benchmark, demo and 0.1.0 README`
- [ ] **Step 6: Open the release pull request** `release: 0.1.0` from `release/0.1.0` to `main` (workflow section 8), with plan 02 marked done. Its body lists the owner's steps: merge it with a merge commit; merge release-please's `chore(main): release 0.1.0` after checking version and CHANGELOG; confirm that tag `v0.1.0` ran `publish.yaml` and the version is on pub.dev (after any pub.dev setting Task 18 names); remove `release-as` and `bootstrap-sha` in a pull request to `develop`; open and merge `chore(release): sync main into develop` with a merge commit. Do not merge it, tag or publish.

### Task 18: Publish trigger and release version

**Branch:** `ci/02-18-publish-trigger`. Merged into `develop` before Task 17 step 6.

**Files:**
- Modify: `.github/workflows/release-please.yaml`, `.github/workflows/publish.yaml`, `release-please-config.json`, `docs/engineering/workflow.md` (section 8)

**Interfaces:**
- Produces: a release that publishes itself once release-please's pull request is merged, with no long-lived secret.

- [ ] **Step 1: Check the premise** in GitHub's documentation ("Triggering a workflow from a workflow") and in dart.dev's automated publishing guide: a tag that release-please creates with the default `GITHUB_TOKEN` starts no new workflow run, except `workflow_dispatch` and `repository_dispatch`. Record what pub.dev accepts (tag push, `workflow_dispatch` on a tag ref, environments).
- [ ] **Step 2: Implement the simplest fix without a stored secret** that the sources support, for example: the release-please job dispatches `publish.yaml` on the tag ref when `release_created` is true (`actions: write` on that job only), and `publish.yaml` accepts `workflow_dispatch`. A change needed on pub.dev (such as enabling publishing from `workflow_dispatch` events) is described for the owner, never made here.
- [ ] **Step 3: Set `"release-as": "0.1.0"`** on the `.` package of `release-please-config.json`. Without it a `feat` takes `0.1.0-dev.1` to `0.2.0-dev.1` (workflow section 8). `bootstrap-sha` stays until the first release of release-please's own.
- [ ] **Step 4: Document** the trigger and the owner's pub.dev step in workflow section 8, with the references.
- [ ] **Step 5: Commit.** `ci: dispatch the publish workflow from release-please`

# Affected Tests (0.3.0) Implementation Plan

> Revised on 2026-11-21 after ADR-0018 and the 0.2.0 code.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `0.3.0`: `tests/affected` on pre-push and CI, `why`, `l10n/unused-key`, a content-addressed facts cache, SARIF and JUnit reporters for `ci`, and pub workspaces.

**Architecture:** Test selection is a pure function of the import graph built in 0.1.0, and the closure it also computes is what the divergence test of [ADR-0018](../adr/0018-affected-tests-run-against-validated-snapshot.md) judges. Running tests is the first feature that executes project code, isolated behind a `TestRunner` port whose only adapter lives in `infrastructure/dart/`. Syntactic facts become cacheable by blob id, which is what makes whole-package rules affordable.

**Tech Stack:** As plan 03. No new runtime dependency: SARIF is written with `dart:convert`, JUnit with an XML writer of our own, the cache key hashes with the approved `crypto`.

**Spec:** [`specs/rules.md`](../specs/rules.md) `tests/affected`, `l10n/unused-key`, `pubspec/lockfile-out-of-sync`; [`specs/cli.md`](../specs/cli.md) 3.5, 3.8, 7; [`specs/dart-toolchain.md`](../specs/dart-toolchain.md) 2, 3, 6, 6.1, 7; [`specs/git.md`](../specs/git.md) 4.3.1, 5; [`specs/config.md`](../specs/config.md) 3; [`engineering/security.md`](../engineering/security.md) S1, S3, S14; [ADR-0017](../adr/0017-hand-written-lexer-for-declaration-and-test-call-facts.md), [ADR-0018](../adr/0018-affected-tests-run-against-validated-snapshot.md). Signatures: [`architecture.md`](../architecture.md) 4, 5.7.

## Order

Dependencies: Task 2 needs 1. Task 5 needs 3 and 4. Task 6 needs 3 and 5. Task 8 needs 7. Task 9 needs 4 and 5. Task 10 is last. Tasks 1, 3, 4 and 7 depend on nothing before them.

Tasks touch overlapping files (`composition.dart`, `pipeline_check_context.dart`, `ci_command.dart`, the generated `docs/rules.md`), so run them one at a time in this order: **1, 3, 4, 2, 5, 7, 8, 6, 9, 10.** Two writers may work in parallel only on Tasks that share no file: for example 3 and 4 (disjoint), or 1 and 7. 7 and 8 both edit `ci_command.dart`, so 8 stacks on 7.

## Global Constraints

- Everything in the Global Constraints of plans 01–03.
- The only executables started are `git` and the resolved SDK's `dart` or `flutter` (S1). Test file paths are passed as arguments after `--`.
- Only files under `lib/src/infrastructure/dart/` start `dart test` or `flutter test`; `test/architecture/layering_test.dart` fails on any other (Task 4). A check never starts a process: it uses `CheckContext.tests`.
- The cache lives under `<git common dir>/stagelatch/cache/` and nowhere else (S3, `dart-toolchain.md` 6.1). A cache failure of any kind is a miss, never an error. A cache hit must be indistinguishable from recomputation; a test proves it, and the determinism test runs with a cold and a warm cache.
- `tests/affected` never runs on `pre-commit`. On `pre-push` and `ci` it starts no process unless the divergence test passes immediately before the first process, and it discards the results when the test fails after the last one (ADR-0018).
- A rule that needs the declarations, calls or identifiers of a file skips a file whose facts are not `isWellFormed` and never reads an empty list as "none" (ADR-0017).
- Registering a rule changes generated and spelled-out output: regenerate `docs/rules.md` with `dart run tool/generate_rules_doc.dart` in the same pull request, and update every test or golden that spells the check table of a hook or the output of `init` (`test/application/config/default_hooks_test.dart`, `test/acceptance/*`, `test/goldens/`). Run the whole suite to find them.
- Specs for everything below are already written. If a task finds behaviour a spec leaves open, write it into the spec first, in the same pull request, and list it under "Deviations".
- A commit of this plan never carries `!` or a `BREAKING CHANGE:` footer (`workflow.md`, section 8).

## What 0.2.0 already has (verified against the code)

- `GitRepository.divergingFromWorktree(SnapshotRef)` exists and is tested in `test/infrastructure/git/git_cli_repository_test.dart`. It is `git diff --name-only -z --no-renames [<sha>]` only: it knows nothing of untracked files, so it is one input of the divergence test, not the whole of it.
- `CheckContext` has no `tests` and no divergence member (`architecture.md` listed them ahead of the code). `Pipeline` builds a `PipelineCheckContext` per phase around a `LazyToolchain`; the import graph is built inline in `PipelineCheckContext.importGraph`.
- `isTestFile` is in `lib/src/checks/tests/test_key.dart`. `domain` may not import `checks`, so test selection is a `checks/tests/` file, and `application/why/` imports it.
- `ImportGraph` stores reverse edges only (`dependentsOf`, `shortestChain`). Forward edges, the forward closure and directive locations are new.
- `SyntacticFacts.extract` leaves `identifiers` empty and `SdkDartToolchain.facts` reads the blob on every call; there is no cache. `SdkDartToolchainFactory` is `const` with no fields, and `DartToolchainFactory.create` keeps its signature (the cache reaches the toolchain through the factory's constructor).
- `default_hooks.dart` already lists `tests/affected` in the `pre-push` default and so in the `ci` union, filtered by the catalog. Registering the rule is what puts it into `init`'s output and into every default pre-push report.
- `ci_command.dart` validates `--reporter` against `console`, `json`, `github`; `cli.md` 3.5 now lists five. `run` keeps `console` and `json`.
- `MaterializedSnapshot.write` copies the package config of each `package.root`; `SdkDartToolchain._requirePackageConfig` and `Doctor` D9 name that same path per package.
- `test/fixtures/dart_app` is a Dart package without `test/` and without a dependency on `package:test`; `test/support/fixture_package.dart` copies it and runs `dart pub get --offline`. The dogfood job in `.github/workflows/ci.yaml` runs `dart pub get` in the root, `benchmark` and `test/fixtures/dart_app`.
- Observed with Dart 3.13.4, `test` 1.33.0 (JSON protocol 0.1.1) and Flutter 3.47.5 while revising this plan (re-verify in Task 4 before recording fixtures):
  - `dart test --reporter json -- <file>` writes one JSON object per line. A failing test has an `error` event with `isFailure: true`, then `testDone` with `result: "failure"`; an exception gives `result: "error"`; a skipped test has `testDone` `skipped: true`, `result: "success"`. `testStart.test.name` is the full name (`g fails`) and carries `line`, `column` and a `file:` `url` that is a real path (on macOS `/private/tmp/...`, so the repository root must be resolved through symlinks before relativizing).
  - A compile error is not a `hidden` test: the pseudo test named `loading <file>` gets an `error` event whose text starts `Failed to load "<file>":` and the real diagnostic on its next line, then `testDone` `result: "error"`, `hidden: false`.
  - `flutter test --machine` writes the same objects, with absolute `suite.path`, and also blank lines and a JSON **array** (`[{"event":"test.startedProcess",...}]`). Only objects with a string `type` are events.
  - After `dart pub get` in a pub workspace, members have no `.dart_tool/package_config.json` and no `pubspec.lock`; the root's config lists every member (`rootUri: "../packages/a"`), and `dart test` run in a member's directory resolves through it. The lock marks only the root pubspec's dependencies `direct`; a member's are `transitive`, and members are not in the lock. Globs in `workspace:` need language version 3.11.

## Review Focus

- **An ill-formed Dart file in a package with `l10n.yaml`.** Expected: no `unused-key` finding for that package (its identifier set is empty, not "no uses"). Owner: Task 2.
- **Identifiers are every identifier and keyword token**, including those inside `'${...}'`; comments and string text do not count. Owner: Task 2.
- **A key used only in a generated file or in another package.** Expected: still reported. Owner: Task 2.
- **The cold `pre-commit` with `l10n/unused-key` on the 2,435-file corpus.** Expected: at most 2 s on `s3` and `s10`. Over that, stop and ask; do not weaken a default. Owner: Task 2 (gate), Task 10 (published numbers).
- **Two linked worktrees, or two processes, writing one cache key; Windows refusing to rename over an existing file.** Expected: one complete entry, no error. Owner: Task 1.
- **A corrupted, truncated, wrong-version or unwritable cache, and a cache directory that is a symlink out of the common directory.** Expected: recomputed silently, verdict unchanged, nothing written outside. Owner: Task 1.
- **The same blob at two paths, and the same blob with two `tests.functions` sets.** Expected: locations carry the requested path; the sets never share an entry. Owner: Task 1.
- **A test that reaches a changed file only through a `package:` self-import, a `part`, or an `export`.** Expected: selected. Owner: Task 3.
- **A deleted source file, and a renamed one.** Expected: importers of the old path are selected; a deleted test file is not. Owner: Task 3.
- **A deleted `pubspec.lock`.** Expected: selects nothing (it is not in the snapshot). Owner: Task 3.
- **Test tool output that is not an event object** (blank lines, text, a JSON array, a truncated object, a line over 1 MiB). Expected: ignored. Owner: Task 4.
- **A test declared through a helper in another file.** Expected: located at the declaration in the test file (`root_url`). Owner: Task 4.
- **A non-zero exit with no failure and no error to quote.** Expected: startup error naming the exit code, never a green verdict. Owner: Task 4.
- **A hung or abandoned test process.** Expected: the child is killed and awaited in a `finally`; stdin is closed at once. Owner: Task 4.
- **A test path with shell metacharacters when the executable is `flutter.bat`.** Expected: refused as a startup error, never passed (S14). Owner: Task 4.
- **A change that no test depends on.** Expected: no divergence call, no process, no finding. Owner: Task 5.
- **An affected test that imports an untracked non-ignored file, and the same import of an ignored one.** Expected: skip with the warning, and a normal run (AC-25). Owner: Task 5.
- **A pre-push of a branch that is not checked out.** Expected: the warning, push allowed (AC-26). Owner: Task 5.
- **`pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, fixtures, `dart_test.yaml`, `build.yaml`** (AC-27). Owner: Task 5.
- **An edit made while the tests run.** Expected: results discarded and the warning reported. Owner: Task 5.
- **A file in the pushed commit that is untracked in the working tree.** Expected: divergent. Owner: Task 5 (adapter test).
- **`analyze` and `tests/affected` on pre-push** run concurrently in the verify phase; `dart test` works on the working tree and the analysis server on the materialized copy, so they share no write. Owner: Task 5 (acceptance run of both).
- **`ci --all`** selects every test (every file is changed). Owner: Task 5.
- **`why` with no upstream and no remote default branch.** Expected: usage error, exit 64. Owner: Task 6.
- **`why` for a test selected only by a changed `pubspec.yaml`.** Expected: the configuration chain. Owner: Task 6.
- **SARIF for a path with spaces and non-ASCII characters, an analyzer rule no check declares, and no run at all.** Expected: valid document. Owner: Task 7.
- **XML 1.0 forbidden characters, `]]>`, and markup in a message.** Expected: cannot break the document. Owner: Task 8.
- **A workspace member whose lock and package config live at the workspace root; a dependency that names another member.** Expected: found at the root; the member dependency is not "missing from the lock". Owner: Task 9.
- **A lock change in a workspace.** Expected: widens to every member's tests. Owner: Task 9.
- **This repository's own pre-push and dogfood CI run its whole suite.** Expected: measured; if the job outgrows the slowest matrix cell, ask the owner (ADR-0018 gives the `ci` list escape). Owner: Task 10.

---

### Task 1: Content-addressed cache for facts

**Branch:** `feat/04-01-cache`

**Files:**
- Create: `lib/src/application/ports/cache.dart`, `lib/src/infrastructure/io/file_cache.dart`, `lib/src/infrastructure/dart/facts_codec.dart`, `lib/src/infrastructure/dart/cached_facts.dart`, `test/support/fake_cache.dart`, `tool/update_facts_golden.dart`, `benchmark/bin/cache.dart`
- Create: `test/fixtures/facts_corpus/*.dart.txt` (a handful of sources: directives with conditional imports, annotated declarations, test calls with `solo` and `skip`, identifiers in interpolation, an unterminated string), `test/goldens/facts/corpus_v1.json`
- Modify: `lib/src/infrastructure/dart/sdk_dart_toolchain.dart` (`SdkDartToolchainFactory({Cache? cache})`, `facts` through `CachedFacts`), `lib/src/cli/composition.dart` (build `FileCache(commonDir: layout.commonDir)` and pass it), `test/acceptance/determinism_test.dart`
- Test: `test/infrastructure/io/file_cache_test.dart`, `test/infrastructure/dart/facts_codec_test.dart`, `cached_facts_test.dart`, `facts_corpus_test.dart`

**Interfaces:**
- Consumes: `SyntacticFacts`, `SnapshotFiles.entry` (the blob id and mode of an entry), `RepoLayout.commonDir`, `package:crypto`.
- Produces: `Cache { Future<String?> read(String namespace, String key); Future<void> write(String namespace, String key, String value) }`; `FileCache({required String commonDir})`; `const int factsFormatVersion = 1`; `String encodeFacts(DartFileFacts)`; `DartFileFacts? decodeFacts(String text, RepoPath path)`; `CachedFacts({required SyntacticFacts extractor, required Cache cache})` with `Future<DartFileFacts?> facts(SnapshotFiles files, RepoPath path)`; `SdkDartToolchainFactory({Cache? cache})`.

**Decisions fixed here** (specified in `dart-toolchain.md` 6.1; `security.md` S3 now says `<git common dir>/stagelatch/cache/`):
- **Version and key.** One `factsFormatVersion` covers the encoding and the extractor's behaviour. The namespace is `facts-v<factsFormatVersion>` and the key is `<blob id>-<sha256 hex of the sorted tests.functions joined by "\n">`. A golden test over `test/fixtures/facts_corpus` reads `test/goldens/facts/corpus_v<factsFormatVersion>.json`: a PR that changes what the lexer or a recognizer produces fails it until the version is raised and the golden regenerated with `dart run tool/update_facts_golden.dart`; raising the version without a golden fails it too.
- **Wiring.** `SdkDartToolchainFactory` receives the `Cache`; `create` is unchanged. `SdkDartToolchain.facts` calls `CachedFacts.facts` when it has a cache, else extracts as today. On a hit the blob is not read. A mode that is not regular or executable, and a null `readText`, give null and store nothing.
- **Failure model.** `CachedFacts` treats any `Exception` from the cache and any undecodable entry as a miss, recomputes and writes again. `FileCache.read` returns null and `write` is a no-op for every I/O failure.
- **Writes.** Create a temporary directory inside the shard directory with `Directory.createTemp` (no `Random`, no clock), write the value there, `rename` it onto the key, delete the temporary directory in a `finally`. A `FileSystemException` from `rename` is swallowed: the entry exists already or the write is abandoned. The constructor takes an optional rename function for the test that injects the failure.
- **Containment (S3).** On first write, create `<commonDir>/stagelatch/cache`, resolve symlinks of it and of `commonDir`, and use the cache only when the first is within the second; otherwise every call is a no-op or a miss. Nothing is created by the constructor or by `read`.
- **Validation.** `namespace` must match `[a-z0-9-]+` and `key` `[0-9a-f-]{2,}`; anything else is an `ArgumentError` (a bug, not an I/O failure).
- **Codec.** Canonical JSON with `v`, `isWellFormed`, `directives`, `annotatedDeclarations` (with `tokenHash`), `testCalls`, `identifiers` (sorted), positions only. `DartFileFacts` has no `==`; tests compare `encodeFacts` of both sides and spot-check fields.

- [ ] **Step 1: Write the failing tests.**

```dart
// file_cache_test.dart
test('a value written is read back; an unknown key is null', () async { /* ... */ });
test('an entry is stored at <commonDir>/stagelatch/cache/<namespace>/<first two characters>/<key>', () async {
  await cache.write('facts-v1', 'abcdef-12', 'v');
  expect(File('$common/stagelatch/cache/facts-v1/ab/abcdef-12').readAsStringSync(), 'v');
});
test('a namespace or key outside the allowed alphabet is an ArgumentError', () {
  expect(() => cache.write('facts', '../x', 'v'), throwsArgumentError);
  expect(() => cache.write('facts', 'a.b', 'v'), throwsArgumentError);
  expect(() => cache.write('Facts', 'abcd', 'v'), throwsArgumentError);
  expect(() => cache.write('facts', 'a', 'v'), throwsArgumentError);
});
test('the constructor and read create nothing', () async { expect(Directory('$common/stagelatch').existsSync(), isFalse); });
test('a reader never sees a partial entry', () async { /* one writer of 1 MiB, 200 concurrent reads: each is null or the whole value */ });
test('twenty concurrent writers of one key leave one complete entry and no temporary directory', () async { /* listSync of the shard has one entry */ });
test('a rename that fails is not an error and keeps the existing entry', () async { /* inject a rename that throws FileSystemException */ });
test('an unwritable directory makes write a no-op and read a miss', () async { /* chmod 0500 */ }, testOn: '!windows');
test('a stagelatch directory that is a symlink out of the common directory is not used', () async { /* the target stays empty */ }, testOn: '!windows');

// facts_codec_test.dart
test('encoding what was decoded gives the same text', () { /* every file of the corpus */ });
test('the path is not stored: decoding for another path puts that path in every location', () { /* a.dart, lib/b.dart */ });
test('identifiers are encoded sorted, so insertion order never changes the text', () { /* ... */ });
test('a file that is not well formed round-trips with empty declarations and calls', () { /* ... */ });
test('tokenHash, groups, solo and skip survive', () { /* spot-check values */ });
test('a document of another version is not decoded', () { expect(decodeFacts(text.replaceFirst('"v":1', '"v":2'), path), isNull); });
test('garbage never throws: every strict prefix of a valid document, and wrongly typed members, decode to null', () { /* '', '{', '[]', '{"v":1}', '{"v":1,"directives":"x"}' */ });

// cached_facts_test.dart
test('the first request extracts and stores; the second is served without reading the blob', () async { /* count readText calls on the snapshot */ });
test('a hit equals recomputation, with the requested path in every location', () async { /* the same blob at a.dart and lib/b.dart */ });
test('the key is <blob id>-<sha256 of the sorted test functions>', () async { /* FakeCache keys */ });
test('different test functions never share an entry', () async { /* {test} then {test, myTest} on a file calling myTest('x') */ });
test('a corrupted entry is a miss and is overwritten', () async { /* FakeCache preloaded with garbage */ });
test('an exception from the cache is a miss', () async { /* FakeCache that throws */ });
test('a symlink, a gitlink, an absent file and a binary file give null and store nothing', () async { /* ... */ });
test('a file that is not well formed is cached and restored as not well formed', () async { /* ... */ });

// facts_corpus_test.dart
test('the facts of the fixed corpus equal the golden of this version', () {
  // message when different: 'Raise factsFormatVersion, then run: dart run tool/update_facts_golden.dart'
});

// determinism_test.dart
test('a cold cache, a warm cache and a deleted cache give the same JSON report', () async { /* tests/solo scenario; stabilize durations; the cache directory exists after the first run */ });
```

- [ ] **Step 2: Run.** Expected: FAIL, the new files do not exist.
- [ ] **Step 3: Implement** as decided above. `Composition.create` builds `FileCache` from `layout.commonDir`; a hook run with `GIT_DIR` set already has the right `commonDir`.
- [ ] **Step 4: Measure.** `benchmark/bin/cache.dart` (the benchmark depends on `stagelatch` by path, ADR-0017) times `facts` over every `.dart` file of the 2,435-file corpus with an empty cache, then with a warm one, in the same process and in fresh processes. Put both numbers in the pull request. If the warm run is not faster than the cold one, stop and ask: the cache must pay for itself, and Task 2 adds the identifier sets to every entry.
- [ ] **Step 5: Run** all four commands. Expected: PASS.
- [ ] **Step 6: Commit.** `feat(cache): cache syntactic facts by blob id`

### Task 2: Identifier facts and `l10n/unused-key`

**Branch:** `feat/04-02-l10n-unused-key` (after Task 1)

**Files:**
- Create: `lib/src/checks/l10n/unused_keys.dart`, `test/goldens/facts/corpus_v2.json`, `benchmark/scenarios/s3-l10n/`, `benchmark/scenarios/s10-l10n/` (the `s3` and `s10` patches plus a staged `l10n.yaml` and a 200-key template, when the corpus has none)
- Modify: `lib/src/infrastructure/dart/syntactic_facts.dart` (fill `identifiers`), `lib/src/infrastructure/dart/facts_codec.dart` (`factsFormatVersion = 2`), `lib/src/checks/l10n/l10n_check.dart`, `lib/src/checks/l10n/l10n_rules.dart`, `docs/rules.md` (regenerated), `benchmark/bin/measure_cli.dart` (if the new scenarios need it), `test/fixtures/facts_corpus/*.dart.txt` (an interpolated identifier), `test/support/acceptance.dart` and the tests that spell the l10n rows only if the full suite shows a difference
- Delete: `test/goldens/facts/corpus_v1.json`
- Test: `test/infrastructure/dart/identifiers_test.dart`, `test/checks/l10n/unused_keys_test.dart`; extend `test/checks/l10n/l10n_check_test.dart`

**Interfaces:**
- Consumes: `DartFileFacts.identifiers` and `isWellFormed`, `CheckContext.dart.facts`, `PackageMap.packageOf`, `readL10nSetup`, `ArbDocument`, `CodegenSettings.generatedSuffixes`.
- Produces: `SyntacticFacts.extract` fills `identifiers`; `unusedKeyRule` (default `warning`) registered in `l10nRuleDescriptors`; `Future<List<Finding>> unusedKeyFindings(CheckContext context, L10nSetup setup, ArbDocument template, DartPackage package)`.

**Decisions fixed here** (specified in `rules.md` `l10n/unused-key` and `dart-toolchain.md` 6):
- `identifiers` is every `TokenKind.word` token (the lexer has no keyword table, which is what ADR-0017 means by "identifier and keyword"), interpolated expressions included. A file that is not well formed has an empty set. The version is raised to 2 and the golden regenerated, because stored v1 entries have no identifiers.
- The rule looks at a package when `l10n.yaml` or an ARB file of it changed (as today) or when a `.dart` file that belongs to it was added, modified, deleted or renamed (either path). It skips the package when the template is missing or not an object, and when any scanned file is not well formed.
- Scanned files: `snapshot.list()` entries with extension `.dart`, regular or executable, `packageOf(path) == package`, not under `setup.outputDir`, not ending in a `codegen.generated_suffixes` suffix. Facts are requested concurrently (`Future.wait`) and served by the cache.
- `_package` in `l10n_check.dart` returns early when neither `missing-key` nor `placeholder-mismatch` is enabled; restructure so `unused-key` still runs, and so a package looked at only because of a Dart change runs nothing else.

- [ ] **Step 1: Write the failing tests.**

```dart
// identifiers_test.dart
test('identifiers are the words of the code, not of comments or strings', () {
  expect(ids("void f() { l10n.checkoutTitle; } // inComment 'inString'"), containsAll(['f', 'l10n', 'checkoutTitle']));
  expect(ids("// inComment\nvar s = 'inString';"), isNot(containsAny(['inComment', 'inString'])));
});
test('keywords are identifiers too (ADR-0017)', () { expect(ids('class Foo {}'), containsAll(['class', 'Foo'])); });
test('an identifier inside an interpolation counts', () {
  expect(ids(r"var s = '${l10n.legacyBanner} $other';"), containsAll(['l10n', 'legacyBanner', 'other']));
});
test('a file that is not well formed has no identifiers', () { expect(facts("var s = 'unterminated;").identifiers, isEmpty); });
test('identifiers are linear on a hostile 1 MiB file', () { /* S6, same shapes as facts_adversarial_test */ });

// unused_keys_test.dart
test('a key referenced nowhere is reported at the template key', () async {
  expect(f.single.message, 'Key "legacyBanner" is not referenced by any Dart file.');
  expect(f.single.severity, Severity.warning);
  expect(f.single.location.path, RepoPath('lib/l10n/app_en.arb'));
});
test('a key used through l10n.key, a getter chain or an interpolation is used', () async { /* ... */ });
test('a reference in a generated file does not count', () async { /* under output-dir, and *.g.dart */ });
test('a reference in another package does not count', () async { /* packages/b/lib/x.dart */ });
test('the rule scans the whole package, not the changeset', () async { /* the only use is in an unchanged file */ });
test('the rule looks at the package when a Dart file of it changed even if no ARB did', () async { /* removing the last use */ });
test('a deleted or renamed Dart file triggers it, under either path', () async { /* ... */ });
test('a Dart file of another package does not trigger it', () async { /* ... */ });
test('a package with a file that is not well formed produces no finding', () async { /* ... */ });
test('metadata keys starting with @ are not keys', () async { /* ... */ });
test('the rule can be off or an error through rules:', () async { /* isEnabled false: no facts requested */ });
```

- [ ] **Step 2: Run.** Expected: FAIL, `identifiers` is empty and the rule does not exist.
- [ ] **Step 3: Implement** as decided above. Register `unusedKeyRule` with summary `A key of the template is not used by any Dart file.`
- [ ] **Step 4: Measure the gate.** Run `benchmark/bin/measure_cli.dart --hook pre-commit` on `s3-l10n` and `s10-l10n`, cold (empty cache and empty analysis cache) and hot, and put the table in the pull request. **If the cold pre-commit exceeds 2 s on either, stop and ask the owner.** Do not change the default hook list, the rule's scope or its trigger to make it fit; the owner chooses (for example, reporting only newly unused keys would change the spec).
- [ ] **Step 5: Regenerate** `docs/rules.md`; run all four commands. Expected: PASS.
- [ ] **Step 6: Commit.** `feat(checks): add l10n/unused-key`

### Task 3: Affected test selection

**Branch:** `feat/04-03-affected-selection`

**Files:**
- Create: `lib/src/checks/tests/affected_tests.dart`
- Modify: `lib/src/domain/dart/import_graph.dart` (forward edges, `dependenciesOf`, `directiveOf`)
- Test: `test/checks/tests/affected_tests_test.dart`; extend `test/domain/dart/import_graph_test.dart`

**Interfaces:**
- Consumes: `ImportGraph`, `ChangeSet`, `PackageMap`, `isTestFile` (`lib/src/checks/tests/test_key.dart`).
- Produces: `ImportGraph.dependenciesOf(Set<RepoPath>) -> Set<RepoPath>` and `ImportGraph.directiveOf(RepoPath importer, RepoPath target) -> Location?` (`dart-toolchain.md` 3); `AffectedTests selectAffectedTests({required ImportGraph graph, required ChangeSet changes, required PackageMap packages, required Set<RepoPath> snapshotPaths})` and `AffectedTests` with `testFiles`, `byPackage`, `sources`, `widenedBy`, `closure` (`architecture.md` 5.7).

**Decisions fixed here** (ADR-0018, `rules.md` `tests/affected`):
- **Sources.** The `.dart` paths of present changes, the `.dart` paths of deleted changes, and every `previousPath` with extension `.dart`. `testFiles` is `graph.dependentsOf(sources)` restricted to `isTestFile`, to `snapshotPaths`, and minus deleted and previous paths, sorted. A changed test file selects itself because `dependentsOf` includes its inputs.
- **Widening.** For every change whose path (or `previousPath`) has basename `pubspec.yaml` or `analysis_options.yaml`, and for every *present* change whose basename is `pubspec.lock`: the owning package is `packages.packageOf(path)` (skip when null) and every test file of it in `snapshotPaths` is selected; record the path in `widenedBy`. A deleted lock selects nothing. This task uses the package itself; Task 9 widens a workspace root's lock to every member.
- **Closure.** `graph.dependenciesOf(testFiles)` (forward closure, edge targets absent from the snapshot included), plus for each package that owns a selected test its `pubspec.yaml` and `analysis_options.yaml` (whether or not they are in the snapshot, so that the divergence test can look at an untracked one) and its `pubspec.lock` only when that path is in `snapshotPaths`.
- Sorting: every list is sorted by path; `byPackage` by package root, repository root first.

- [ ] **Step 1: Write the failing tests.**

```dart
// import_graph_test.dart
test('dependenciesOf follows import, export and part edges forward, inputs included, sorted', () { /* ... */ });
test('edges to targets absent from the snapshot are followed and the targets are in the result', () { /* ... */ });
test('a cycle of imports terminates', () { /* ... */ });
test('directiveOf is the first directive of the importer that resolves to the target', () { /* source order; null without an edge */ });

// affected_tests_test.dart
test('a changed test file selects itself', () { /* test/a_test.dart modified -> [test/a_test.dart] */ });
test('a test importing a changed file directly or transitively is selected', () { /* lib/a.dart <- lib/b.dart <- test/t_test.dart */ });
test('package: self-imports, part files and exports are followed', () { /* ... */ });
test('a test that does not depend on any change is not selected', () { /* ... */ });
test('a deleted source file selects the tests that still import it', () { /* the graph keeps the dangling edge */ });
test('a renamed source file selects the importers of its old path and its new one', () { /* ... */ });
test('a deleted test file is not selected', () { /* ... */ });
test('a changed pubspec.yaml or analysis_options.yaml selects every test of that package and no other', () {
  expect(selection.byPackage.keys.single.root, RepoPath('packages/ui'));
  expect(selection.widenedBy, {RepoPath('packages/ui/pubspec.yaml'): [uiPackage]});
});
test('a pubspec.lock in the snapshot widens like a pubspec; a deleted lock selects nothing', () { /* ... */ });
test('a changed file outside every package selects nothing', () { /* ... */ });
test('files outside test/ ending in _test.dart are not tests', () { /* ... */ });
test('the closure is the forward import closure of the tests, edge targets absent from the snapshot included', () { /* ... */ });
test('the closure holds the owning packages pubspec.yaml and analysis_options.yaml even when absent, and the lock only when in the snapshot', () { /* ... */ });
test('the closure does not hold files that merely depend on a selected test', () { /* ... */ });
test('results are sorted, and grouped by package with the repository root first', () { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL, the functions do not exist.
- [ ] **Step 3: Implement.** `ImportGraph.build` keeps, per importing file, its edges `(target, directive location)` in source order, next to the reverse map; `dependenciesOf` is an iterative walk over them (no recursion, security S6). `selectAffectedTests` is pure.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): select tests affected by a changeset`

### Task 4: Test runner

**Branch:** `feat/04-04-test-runner`

**Files:**
- Create: `lib/src/domain/dart/test_runner.dart`, `lib/src/application/ports/test_runner_factory.dart`, `lib/src/infrastructure/dart/test_command.dart`, `lib/src/infrastructure/dart/test_event_parser.dart`, `lib/src/infrastructure/dart/process_test_runner.dart`, `test/support/fake_test_runner.dart`, `test/support/fake_process.dart`
- Create: `test/fixtures/test_events/all_pass.jsonl`, `one_failure.jsonl`, `error_result.jsonl`, `compile_error.jsonl`, `helper_location.jsonl`, `flutter_noise.jsonl`, `README.md` (the SDK versions, the date and the exact commands the recordings were made with)
- Modify: `test/architecture/layering_test.dart` (a second spawn rule, like the language-server and format one), `test/support/fixture_package.dart` (`copyFixturePackage({bool withTestPackage = false})` writes a `dev_dependencies: test` constraint into the copy before `pub get`; `pubGetOffline(String root)` for acceptance repositories)
- Test: `test/infrastructure/dart/test_event_parser_test.dart`, `test_command_test.dart`, `process_test_runner_test.dart`; `test/domain/dart/test_runner_test.dart` (equality of `TestFailure`)

**Interfaces:**
- Consumes: `ResolvedSdk`, `DartPackage`, `RepoPath`.
- Produces: `TestFailure { RepoPath file; int line; int column; String name }` with `==`; `TestRunResult { List<TestFailure> failures; String? startupError }`; `TestRunner { Future<TestRunResult> run(DartPackage package, List<RepoPath> files) }`; `TestRunnerFactory { TestRunner create({required ResolvedSdk sdk, required String repoRoot}) }`; `TestCommand { String executable; List<String> arguments; RepoPath? directory }`; `List<TestCommand> testCommands({required ResolvedSdk sdk, required DartPackage package, required List<RepoPath> files})`; `TestEventParser({required String repoRoot, required RepoPath fallbackFile, p.Context? context})` with `add(String line)` and `TestRunResult finish({required int exitCode, String standardError = ''})`; `ProcessTestRunner({required ResolvedSdk sdk, required String repoRoot})` and `ProcessTestRunnerFactory`.

**Decisions fixed here** (`rules.md` `tests/affected`, `security.md` S14):
- **Confirm before recording.** Run the commands below against the SDKs on the machine, compare with "What 0.2.0 already has" and record every fixture from a real run (the `helper_location` fixture needs a test declared by a helper in another file, to see `root_url`, `root_line`, `root_column`). Write the versions into the fixtures README. CI runners have no Flutter: the Flutter path is covered by inspecting the command and by the recorded `flutter_noise` fixture; end-to-end tests use Dart only.
- **Commands.** Dart: `<dart> --suppress-analytics test --reporter json -- <files>`. Flutter: `<flutter> test --machine -- <files>`. Working directory: the package root. Files are passed relative to the package directory, in path order, split into batches of at most 20,000 characters of arguments (a single longer path is its own batch); batches of one package run one after the other and their results are merged. Start with `Process.start` and an argument list, never a shell; the environment is inherited unchanged; stdin is closed at once.
- **A Flutter package** whose `ResolvedSdk.flutterExecutable` is null returns `TestRunResult(startupError: 'the resolved SDK has no flutter executable')` and starts nothing. On Windows a `.bat` or `.cmd` executable refuses a test path with a control character or any of `"&|<>^%!`: `startupError: 'unsafe test path: <path>'`, nothing started.
- **Parsing.** Output is a stream of lines (`Utf8Decoder(allowMalformed: true)` and `LineSplitter`), never buffered whole. A line is an event when it is at most 1 MiB, starts with `{`, decodes to a map and has a string `type`; everything else (blank lines, text, arrays, truncated JSON) is ignored. Track `testStart` by `test.id`; a test fails when its `testDone` has `result` `failure` or `error`, counted once however many `error` events it had; hidden tests and skipped tests are not failures. A test whose name starts with `loading ` and whose result is not `success` is the startup error, taking the text of its `error` event. Failure location: `root_url`/`root_line`/`root_column` when present, else `url`/`line`/`column`; `url` is mapped to a repository path through `Uri.toFilePath` and `p.relative` against `repoRoot` **resolved through symlinks** (the runner resolves it once); a location outside the repository or without a `url` is `fallbackFile` at 1:1. `finish`: a startup error is the first line of the error text that does not start with `Failed to load` (the first line when none does), one trailing `.` or `:` removed, cut to 300 characters; with no error event and no test started, the first non-empty line of `standardError`; a non-zero `exitCode` with no failure and no startup error is `the test tool exited with code <n>`.
- **Bounds and lifetime.** At most the first 64 KiB of standard error is kept. The process is closed in a `finally`: if it is still running (the parser or the stream threw), `kill()` and await its exit. A process that cannot be started is a startup error naming the OS message, not an exception.
- **Layering.** `layering_test.dart` fails when a file outside `lib/src/infrastructure/dart/` has `Process.` and either `'test'` or `'--machine'`.
- **Seam.** `ProcessTestRunner` takes an optional `ProcessStarter` (`Process.start`'s shape) so tests inspect the command and use `FakeProcess`.

- [ ] **Step 1: Write the failing tests.**

```dart
// test_event_parser_test.dart (values from the recorded fixtures)
test('all passing produces no failure and no startup error', () { expect(parse('all_pass.jsonl', exitCode: 0), const TestRunResult()); });
test('a failing test is reported with file, line, column and full name', () {
  expect(parse('one_failure.jsonl', exitCode: 1).failures.single,
      TestFailure(file: RepoPath('test/b_test.dart'), line: 2, column: 29, name: 'g fails'));
});
test('a test with result error is a failure, counted once however many error events it had', () { /* error_result.jsonl */ });
test('hidden loading tests and skipped tests are not failures', () { /* the skipped test of one_failure.jsonl */ });
test('lines that are not event objects are ignored', () { /* blanks, text, [{"event":...}], truncated JSON, flutter_noise.jsonl */ });
test('a line longer than 1 MiB is dropped unparsed', () { /* ... */ });
test('a compile error is a startup error with the first diagnostic line', () {
  expect(parse('compile_error.jsonl', exitCode: 1).startupError,
      "test/c_test.dart:2:22: Error: A value of type 'String' can't be assigned to a variable of type 'int'");
});
test('no event and a non-zero exit takes the first line of standard error', () { /* ... */ });
test('a non-zero exit with no failure and no error is a startup error naming the exit code', () { expect(r.startupError, 'the test tool exited with code 79'); });
test('the startup error is cut to 300 characters', () { /* ... */ });
test('a test declared through a helper is located at its root location', () { /* helper_location.jsonl */ });
test('urls become repository paths from the package: packages/ui/test/a_test.dart', () { /* ... */ });
test('a url outside the repository falls back to the first file at 1:1', () { /* ... */ });
test('Windows urls and roots are handled', () { /* p.windows: file:///C:/repo/test/a_test.dart against C:\repo */ });

// test_command_test.dart
test('a Dart package runs dart test with the json reporter in its directory, files relative to it', () {
  expect(command.arguments, ['--suppress-analytics', 'test', '--reporter', 'json', '--', 'test/a_test.dart']);
  expect(command.directory, RepoPath('packages/ui'));
});
test('a Flutter package runs flutter test --machine', () { expect(command.arguments, ['test', '--machine', '--', 'test/a_test.dart']); });
test('files are batched at 20,000 characters in path order and nothing is lost or reordered', () { /* 300 paths of 100 characters */ });
test('a path with a space stays one argument', () { /* 'test/a b_test.dart' */ });

// process_test_runner_test.dart
test('a Flutter package without a flutter executable is a startup error and starts nothing', () async { /* starter never called */ });
test('on Windows a .bat executable refuses an unsafe test path and starts nothing', () async { /* test/a&b_test.dart, flutter.bat */ });
test('the environment is inherited unchanged, no shell is used and stdin is closed', () async { /* FakeProcess and starter arguments */ });
test('the child is killed and awaited when the parser or the stream throws', () async { /* FakeProcess.killed */ });
test('a process that cannot be started is a startup error, not an exception', () async { /* ... */ });
test('batches of one package run in order and their results are merged', () async { /* ... */ });
test('the fixture package: one failing test is found end to end', () async { /* real dart test; the test files are written into the copy at run time, so the repository holds no *_test.dart that this repository would select */ });
test('the fixture package: a compile error is a startup error', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL, none of the files exists.
- [ ] **Step 3: Implement** as decided above. Keep `TestEventParser` synchronous and pure; `ProcessTestRunner` owns the process and the line stream.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(dart): add test runner over machine-readable output`

### Task 5: The `tests/affected` rule

**Branch:** `feat/04-05-tests-affected`

**Files:**
- Create: `lib/src/checks/tests/affected_rule.dart`, `lib/src/application/pipeline/lazy_test_runner.dart`
- Modify: `lib/src/domain/check.dart` (`TestRunner get tests`, `Future<Set<RepoPath>> divergentAmong(Set<RepoPath>)`), `lib/src/checks/tests/tests_check.dart`, `tests_rules.dart` (`affectedRule`), `lib/src/application/pipeline/pipeline.dart` (constructor `testRunners`; `tests` and `divergentAmong` into each context), `pipeline_check_context.dart`, `lib/src/application/ports/git_repository.dart` (`divergentAmong`), `lib/src/infrastructure/git/git_cli_repository.dart`, `lib/src/cli/composition.dart` (`ProcessTestRunnerFactory`), `docs/rules.md` (regenerated)
- Modify (tests and fakes): `test/support/fake_check_context.dart` (`tests`, `divergent` call log and per-call answers), `fake_git_repository.dart`, `test/application/pipeline/pipeline_test.dart`, `toolchain_wiring_test.dart`, `baseline_order_test.dart`, `test/application/baseline/baseline_commands_test.dart`, `test/cli/runner_test.dart`, `ci_command_test.dart` (each constructs a `Pipeline` and needs a fake `TestRunnerFactory`); every test or golden the full suite shows spelling the default pre-push table
- Test: `test/checks/tests/affected_rule_test.dart`, `test/application/pipeline/lazy_test_runner_test.dart`, `test/infrastructure/git/divergent_among_test.dart`, `test/acceptance/ac24_affected_dirty_test.dart`, `ac25_untracked_import_test.dart`, `ac26_not_checked_out_test.dart`, `ac27_package_config_test.dart`

**Interfaces:**
- Consumes: `selectAffectedTests` (Task 3), `TestRunner` and `TestRunnerFactory` (Task 4), `ImportGraph.directiveOf`, `GitRepository.divergingFromWorktree`, `SnapshotFiles.list`.
- Produces: `CheckContext.tests`, `CheckContext.divergentAmong`; `GitRepository.divergentAmong(SnapshotRef, Set<RepoPath>)`; `affectedRule` (default `error`); `Future<List<Finding>> affectedFindings(CheckContext context)`; `LazyTestRunner`; `Pipeline` taking `required TestRunnerFactory testRunners`.

**Decisions fixed here** (ADR-0018, `rules.md` `tests/affected`, `git.md` 5):
- **Sequence of `affectedFindings`.** (1) Return nothing when `context.entry` is `preCommit` or the rule is not enabled. (2) Return nothing unless a present or deleted change, or a `previousPath`, is a `.dart`, `pubspec.yaml`, `pubspec.lock` or `analysis_options.yaml` file. (3) `selectAffectedTests` over `context.importGraph`, `context.changes`, `context.packages` and the set of `context.snapshot.list()` paths; no test files: return nothing, without asking `divergentAmong`. (4) `divergentAmong(closure)`; a non-empty answer is the skip warning, no process. (5) Run each package of `byPackage`, one after the other, `context.tests.run(package, files)`. (6) `divergentAmong(closure)` again, with the same closure; non-empty: discard every result and report the skip warning. (7) Findings: one error per `TestFailure`, one error per startup error.
- **Findings.** `Test failed: <name>.` at `Location(file, Position(line, column), Position(line, column))`; `Tests could not be run: <startupError>.` at `Location.wholeFile(<first file of that package>)`; the skip warning, severity `warning`, message `Affected tests were not run: <n> file(s) they execute differ from the working tree (uncommitted changes, untracked files, or another checked-out commit).` with `<n>` the size of the divergent set. Its location: the first divergent path in path order; when that path is absent from the snapshot and some file of the closure imports it, at `graph.directiveOf(importer, path)` of the first such importer in path order; otherwise `Location.wholeFile(path)`.
- **`GitCliRepository.divergentAmong`.** `divergingFromWorktree(ref)` once; of the remaining candidates, those absent from `files(ref)` for which `FileSystemEntity.typeSync(..., followLinks: false)` is a regular file go through one `git check-ignore --stdin -z` (exit 0 and 1 are both fine, 128 is an `InternalException`); the result is the intersection with the first list, plus the non-ignored existing ones.
- **`LazyTestRunner`** locates the SDK and creates the runner through `TestRunnerFactory` on the first `run`, like `LazyToolchain`; a run that never asks locates nothing.
- Existing pre-push reports gain a `tests` row once the rule is registered; update them.

- [ ] **Step 1: Write the failing tests.**

```dart
// affected_rule_test.dart
test('no affected test: no divergence check, no run, no finding', () async { expect(runner.calls, isEmpty); expect(context.divergentCalls, isEmpty); });
test('on pre-commit nothing runs even when tests are affected', () async { /* EntryKind.preCommit */ });
test('a rule that is not enabled does nothing', () async { /* ... */ });
test('one finding per failed test at its declaration', () async {
  expect(f.single.message, 'Test failed: cart adds an item.');
  expect(f.single.location, Location(RepoPath('test/cart_test.dart'), const Position(12, 3), const Position(12, 3)));
  expect(f.single.severity, Severity.error);
});
test('a startup error is one finding at the first affected file of the package', () async {
  expect(f.single.message, startsWith('Tests could not be run: '));
  expect(f.single.location, Location.wholeFile(RepoPath('test/a_test.dart')));
});
test('uncommitted changes in the closure skip the run with one warning', () async {
  expect(runner.calls, isEmpty);
  expect(f.single.message, 'Affected tests were not run: 2 file(s) they execute differ from the working tree (uncommitted changes, untracked files, or another checked-out commit).');
  expect(f.single.severity, Severity.warning);
});
test('the warning for an untracked import target sits at the import directive of the first importing file', () async { /* ... */ });
test('the warning for a divergent file of the snapshot sits at the file', () async { /* wholeFile */ });
test('divergence after the run discards the results and reports the warning', () async { /* first call {}, second call {path} */ });
test('divergence is asked about the closure the selection computed', () async { expect(context.divergentCalls, [selection.closure, selection.closure]); });
test('uncommitted changes outside the closure do not skip the run', () async { /* the answer is built from the closure only */ });
test('each package is run once, in path order, with its own files', () async { /* two packages */ });
test('a changed pubspec.yaml runs every test of its package', () async { /* ... */ });
test('a run with a failure and a startup error in different packages reports both', () async { /* ... */ });

// lazy_test_runner_test.dart
test('the SDK is not located until a run is asked for', () async { /* ... */ });
test('the runner is created once for several runs', () async { /* ... */ });

// divergent_among_test.dart (real git, @Tags(['git']))
test('a tracked file that differs from the index is divergent', () async { /* ... */ });
test('a file equal to the snapshot is not divergent', () async { /* ... */ });
test('an untracked file absent from the snapshot is divergent when git would track it', () async { /* ... */ });
test('an untracked ignored file is not divergent', () async { /* .gitignore */ });
test('a symlink or a directory at the path is not a regular file', () async { /* testOn: !windows for the symlink */ });
test('a commit that is not checked out: the files of the closure that differ are divergent', () async { /* ... */ });
test('a file in the pushed commit that is untracked in the working tree is divergent', () async { /* ... */ });
test('two thousand candidates are answered with one check-ignore', () async { /* completes; no per-file process */ });

// ac24_affected_dirty_test.dart
//   a pushed commit that breaks a test: blocked with the failure.
//   the same push while the test file has an unstaged edit: push allowed, warning printed.
// ac25_untracked_import_test.dart: AC-25 as written in testing.md (untracked non-ignored import skips; ignored import runs).
// ac26_not_checked_out_test.dart: AC-26 (branch that is not checked out; exit 0 and the warning).
// ac27_package_config_test.dart: AC-27, every case of the scenario in testing.md.
```

AC-24 to AC-27 use a real repository with `stagelatch.yaml` `hooks: {pre-commit: [], pre-push: [tests/affected]}`, a `.gitignore` with `.dart_tool/`, a pubspec with a `dev_dependencies: test` constraint, `pubGetOffline` (Task 4), and the real `dart test`; each reports through `repo.stagelatch(['run', 'pre-push', ...], stdin: ...)` as `ac19_pre_push_test.dart` does. A test that must "not skip" contains a failing test, so a run is visible as exit 1 and a skip as exit 0 with the warning. One of them also lists `analyze` so both run concurrently.

- [ ] **Step 2: Run.** Expected: FAIL, the members and the rule do not exist.
- [ ] **Step 3: Implement** per `specs/rules.md` `tests/affected` and the decisions above. Add `ci --all` to AC-24's file: every test is selected.
- [ ] **Step 4: Run** all four commands, regenerating `docs/rules.md` first. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add tests/affected`

### Task 6: `why`

**Branch:** `feat/04-06-why` (after Tasks 3 and 5)

**Files:**
- Create: `lib/src/application/why/why.dart`, `lib/src/application/packages/import_graph_builder.dart`, `lib/src/cli/commands/why_command.dart`
- Modify: `lib/src/application/pipeline/pipeline_check_context.dart` (`importGraph` through `buildImportGraph`), `lib/src/application/ports/git_repository.dart` and `lib/src/infrastructure/git/git_cli_repository.dart` (`resolveAgainstIndex`, sharing the merge-base step and its error with `_resolveCi`), `lib/src/cli/composition.dart` (`Why? why`), `lib/src/cli/runner.dart` (register the command), `test/support/fake_git_repository.dart`
- Test: `test/application/why/why_test.dart`, `test/application/packages/import_graph_builder_test.dart`, `test/infrastructure/git/why_resolve_test.dart`, `test/cli/why_command_test.dart`

**Interfaces:**
- Consumes: `selectAffectedTests` and `isTestFile` (checks), `ImportGraph.shortestChain`, `buildPackageMap`, `LazyToolchain`, `ConfigLoader`, `GitRepository.files`.
- Produces: `Future<ImportGraph> buildImportGraph({required DartToolchain dart, required SnapshotFiles snapshot, required PackageMap packages})`; `GitRepository.resolveAgainstIndex({String? baseRef}) -> ResolvedRun`; `WhyOrigin`, `WhyChain`, `WhyResult`; `Why(...)` with `Future<WhyResult> explain(RepoPath testFile, {String? baseRef})`; `String renderWhy(WhyResult)`; `WhyCommand`.

**Decisions fixed here** (`cli.md` 3.8, `git.md` 4.3.1):
- **Changeset.** `GitRepository.resolveAgainstIndex` is not a new entry point and not a copy of `resolve`: the base ref comes from `baseRef`, else the upstream, else `refs/remotes/origin/HEAD`; the merge-base step with its usage error is one private helper shared with `_resolveCi`; the diff is `git diff --cached --name-status -z -M <merge base>`. `Why` calls it, then reuses `selectAffectedTests` for selection and `ImportGraph.shortestChain` for chains, so selection logic exists once.
- **Chains.** For the test, for each source of `AffectedTests.sources` in path order whose `shortestChain(source, test)` is non-null: a `changed` or `deleted` chain (deleted for a deleted path and the old path of a rename); for each `widenedBy` entry whose packages include the test's package: a `configuration` chain. A changed test file is a chain of one. The header counts the chains.
- **Rendering** is exactly `cli.md` 3.8; the unaffected message is `<test> is not affected by the current changes.`
- **Usage errors (64).** The test path is not an `isTestFile` of any package of the index, or is not in the index: `<test-file> is not a test file of any package.` No base: `Cannot determine a base. Pass --base <ref>.`
- `why` loads the configuration from the index for `tests.functions`, starts no test process and no analysis server, and closes its toolchain in a `finally`.

- [ ] **Step 1: Write the failing tests.**

```dart
// why_test.dart
test('prints one shortest chain per changed file that reaches the test', () {
  expect(renderWhy(result), '''
test/checkout/cart_test.dart is affected by 1 changed file:

lib/checkout/cart.dart (changed)
  imported by lib/checkout/cart_controller.dart
  imported by test/checkout/cart_test.dart
''');
});
test('the header counts changed files: 2 changed files', () { /* ... */ });
test('chains are in path order of the changed files', () { /* ... */ });
test('a changed test file is its own chain', () { /* 'test/a_test.dart (changed)' only */ });
test('a deleted file and the old path of a rename are labelled (deleted)', () { /* ... */ });
test('a changed pubspec.yaml prints the configuration chain', () {
  expect(renderWhy(result), contains('pubspec.yaml (changed)\n  configures every test of the package at .\n'));
});
test('an unaffected test says so', () { expect(renderWhy(none), 'test/x_test.dart is not affected by the current changes.\n'); });
test('a path that is not a test file of any package is a usage error', () async { /* lib/a.dart; a test file absent from the index */ });
test('no test process and no analysis server is started', () async { /* fake factory records create() */ });

// import_graph_builder_test.dart
test('the graph has an edge for every directive of every .dart file of the snapshot', () async { /* ... */ });

// why_resolve_test.dart (real git, @Tags(['git']))
test('the base is the merge base of --base and HEAD', () async { /* ... */ });
test('the default base is the merge base with the upstream', () async { /* ... */ });
test('without an upstream the remote default branch is used', () async { /* refs/remotes/origin/HEAD */ });
test('no base at all is a usage error with the documented message', () async { /* ... */ });
test('a missing merge base is the same usage error as ci', () async { /* ... */ });
test('staged changes count and unstaged ones do not', () async { /* ... */ });

// why_command_test.dart
test('prints the rendering and exits 0 whether the test is affected or not', () async { /* ... */ });
test('a path that is not a test file exits 64 with the message on stderr', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL, the command and the functions do not exist.
- [ ] **Step 3: Implement** with the decisions above. `PipelineCheckContext.importGraph` and `Why` both call `buildImportGraph`.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(cli): add why command`

### Task 7: SARIF reporter

**Branch:** `feat/04-07-sarif`

**Files:**
- Create: `lib/src/infrastructure/reporters/sarif_reporter.dart`, `test/goldens/sarif/clean.sarif`, `findings.sarif`, `analyzer_rule.sarif`, `unicode_path.sarif`
- Modify: `lib/src/cli/commands/ci_command.dart` (`sarif` as a reporter; the usage message of `cli.md` 3.5), `test/cli/ci_command_test.dart`, `test/cli/reporter_option_test.dart` (the usage-error text)
- Test: `test/infrastructure/reporters/sarif_reporter_test.dart`

**Interfaces:**
- Consumes: `RunReport`, `Finding`, `RuleDescriptor`, `CheckRegistry.descriptorOf`.
- Produces: `SarifReporter(StringSink out, {required String toolVersion, required RuleDescriptor? Function(RuleId) describe}) implements Reporter`.

**Decisions fixed here** (`cli.md` 3.5 and 7, `security.md` S5):
- **`ci` only.** `run` keeps `console|json` and its usage message. `ci` resolves exactly one run, so the reporter writes one SARIF `run`; with no run it writes a valid document with an empty `results`; with more than one it throws `ArgumentError` (not reachable from the CLI). The earlier idea of merging several pipeline runs into one SARIF run is dropped: pre-push has several refs and no SARIF.
- **Encoding.** `jsonEncode` of maps with keys in the documented order, two-space indent, one trailing newline; no string is built by hand. The `uri` is the repository-relative path with each segment percent-encoded (`Uri(pathSegments: ...)`). `describe` is `registry.descriptorOf` from `Composition`; a rule it does not know (an analyzer code) uses its id as `shortDescription.text`.
- **Errors.** On exit 64, 70 or 78 nothing is written to stdout for `sarif` (no error document), and the human message goes to stderr; add that to the usage-error path of `ci_command.dart` and to its test.

- [ ] **Step 1: Write the failing tests.**

```dart
test('matches the golden: version 2.1.0, one run, the driver name, version and the schema', () { /* findings.sarif */ });
test('rules lists each rule that produced a result, once, sorted by id', () { /* ... */ });
test('levels map from severity and regions are 1-based with an exclusive end column', () { /* ... */ });
test('an analyzer rule no check declares uses the rule id as its short description', () { /* analyzer_rule.sarif */ });
test('a path with a space and non-ASCII characters is percent-encoded per segment', () { /* unicode_path.sarif */ });
test('no run gives a valid document with no results', () { /* clean.sarif */ });
test('more than one run is an ArgumentError', () { /* ... */ });
test('ci --reporter sarif prints the document and exits 1 on an error finding', () async { /* ... */ });
test('ci --reporter sarif on a usage error prints nothing on stdout', () async { /* shallow clone message on stderr */ });
test('run does not accept sarif', () async { expect(stderr, contains('Unknown reporter "sarif". Expected console or json.')); });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/cli.md` section 7.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(reporters): add SARIF reporter`

### Task 8: JUnit reporter

**Branch:** `feat/04-08-junit` (after Task 7)

**Files:**
- Create: `lib/src/infrastructure/reporters/junit_reporter.dart`, `lib/src/infrastructure/reporters/xml_writer.dart`, `test/goldens/junit/clean.xml`, `findings.xml`, `invalid_ignore.xml`
- Modify: `lib/src/cli/commands/ci_command.dart` (`junit`), `test/cli/ci_command_test.dart`
- Test: `test/infrastructure/reporters/junit_reporter_test.dart`, `xml_writer_test.dart`

**Interfaces:**
- Consumes: `RunReport` (`timings` for the checks that ran, `findings`).
- Produces: `String escapeXml(String text, {required bool attribute})`; `JunitReporter(StringSink out) implements Reporter`.

**Decisions fixed here** (`cli.md` 7): the testsuite attributes, one testcase per check that ran in registry order, `failures` counts testcases with at least one error finding, warnings go to the testcase's `<system-out>`, an extra last `stagelatch` testcase carries findings whose rule belongs to no check, `time` has three decimals, and characters XML 1.0 forbids are dropped. `ci` only, like SARIF. `xml_writer.dart` is the only file that writes `<` or `&`; no XML dependency.

- [ ] **Step 1: Write the failing tests.**

```dart
test('escaping covers the five entities and drops characters XML 1.0 forbids', () {
  expect(escapeXml('<a & "b">', attribute: true), '&lt;a &amp; &quot;b&quot;&gt;');
  expect(escapeXml('a\u0000b\u000bc', attribute: false), 'abc');
});
test('text escaping leaves quotes alone and attribute escaping does not', () { /* ... */ });
test('one testcase per check that ran; error findings are failures; warnings go to system-out', () { /* findings.xml */ });
test('the testsuite counts checks and failed checks: tests="3" failures="1" errors="0"', () { /* ... */ });
test('a check with two error findings is one failed testcase with two failure elements', () { /* ... */ });
test('a stagelatch/invalid-ignore finding goes to an extra last testcase named stagelatch', () { /* invalid_ignore.xml; absent otherwise */ });
test('a message containing ]]> or markup cannot break the document', () { /* parse the output back with a strict reader */ });
test('time has three decimals', () { /* 1234 ms -> "1.234" */ });
test('ci --reporter junit prints the document; on a usage error stdout is empty', () async { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Elements go through `xml_writer.dart`; the reporter never concatenates repository text.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(reporters): add JUnit reporter`

### Task 9: Pub workspaces

**Branch:** `feat/04-09-workspaces` (after Tasks 4 and 5)

**Files:**
- Create: `test/fixtures/workspace/` (a root `pubspec.yaml` with `workspace:` and two members with `resolution: workspace`; no `*_test.dart` is committed, the acceptance test writes them), `test/acceptance/ac28_workspace_test.dart`
- Modify: `lib/src/domain/package_map.dart` (`workspaceRoots`, `resolutionPackageOf`, `resolutionRootOf`, `workspaceMembersOf`), `lib/src/application/packages/package_map_builder.dart`, `lib/src/checks/pubspec/pubspec_check.dart`, `lib/src/checks/pubspec/lockfile_out_of_sync.dart`, `lib/src/infrastructure/dart/materialized_snapshot.dart`, `lib/src/infrastructure/dart/sdk_dart_toolchain.dart` (`_requirePackageConfig` at the resolution root), `lib/src/application/doctor/doctor.dart` (D9 at the resolution root, one line per distinct location), `lib/src/checks/tests/affected_tests.dart` (the lock of a member is the root's; its change widens to every member)
- Test: `test/domain/package_map_test.dart` (extend), `test/application/packages/workspace_test.dart`, `test/checks/pubspec/workspace_lock_test.dart`, `test/infrastructure/dart/materialized_snapshot_test.dart` (extend), `test/application/doctor/doctor_test.dart` (extend), `test/checks/tests/affected_tests_test.dart` (extend)

**Interfaces:**
- Consumes: `PackageMap`, `buildPackageMap`, `MaterializedSnapshot`, the lock rule, `selectAffectedTests`.
- Produces: `PackageMap(packages, {workspaceRoots})` with `resolutionPackageOf`, `resolutionRootOf`, `workspaceMembersOf` (`architecture.md` 4); `buildPackageMap` filling `workspaceRoots`; `lockfileFindings(..., Set<String> workspaceMemberNames, bool checkDirectUndeclared)`.

**Decisions fixed here** (`dart-toolchain.md` 2, `rules.md` `pubspec/lockfile-out-of-sync` and `tests/affected`, `cli.md` D9):
- **Detection.** A root lists members under `workspace:`; an entry is a directory or, with language version 3.11, a glob (`package:glob`, matched against the directories of the packages found in the snapshot). A member declares `resolution: workspace`. Each member belongs to the nearest enclosing package that lists it; a package declaring `resolution: workspace` that nobody lists resolves on its own. Members of one root share one resolution root.
- **Resolution root users.** `MaterializedSnapshot.write` copies and rewrites each distinct resolution root's `.dart_tool/package_config.json` once (the root's relative `rootUri`s stay relative, so they point into the directory); `SdkDartToolchain` requires the package config at the resolution root and names that path in `Missing <path>. Run: dart pub get`; D9 probes it.
- **Lock rule.** A member's lock is the root's `pubspec.lock`; a changed root lock triggers the rule for every pubspec of the workspace; dependencies that name a member are not compared; the "lists it as a direct dependency" case is checked only for the root pubspec.
- **`tests/affected`.** The package's lock for the closure and for widening is the one at its resolution root, in the closure only when it is in the snapshot; a change to it selects every test of every member (`workspaceMembersOf`). `ProcessTestRunner` keeps the member's directory as the working directory; Step 3 confirms with the workspace fixture and a real `dart test` that this resolves through the root config (it did when this plan was revised). If the SDK in use behaves differently, record the finding in the fixture's README and fix the runner.
- **No ADR is added.** ADR-0018 does not mention workspaces; this extends "its `pubspec.lock`" to where the lock lives. Listed under Deviations of the pull request for the owner to confirm.

- [ ] **Step 1: Write the failing tests.**

```dart
// workspace_test.dart
test('a member with resolution: workspace resolves to the root that lists it', () async { /* resolutionRootOf */ });
test('workspace globs of the root pubspec are matched against the packages of the snapshot', () async { /* packages/* */ });
test('a package that declares resolution: workspace and is listed by nobody resolves on its own', () async { /* ... */ });
test('a package without resolution: workspace is unaffected', () async { /* ... */ });
test('two workspaces in one repository keep their members apart', () async { /* ... */ });
test('workspaceMembersOf lists every package of the root, the root included, and just the package outside a workspace', () { /* ... */ });

// workspace_lock_test.dart
test('lockfile-out-of-sync reads the root pubspec.lock for a member', () async { /* ... */ });
test('a dependency that names another member is not missing from the lock', () async { /* ... */ });
test('a direct entry of the workspace lock is compared with the root pubspec only', () async { /* ... */ });
test('a changed root lock triggers the rule for every pubspec of the workspace', () async { /* ... */ });

// materialized_snapshot_test.dart / doctor_test.dart
test('members share one copy of the root package config', () async { /* ... */ });
test('the missing package config message names the workspace root', () async { /* Missing .dart_tool/package_config.json. Run: dart pub get */ });
test('D9 prints one line per distinct package config location', () async { /* ... */ });

// affected_tests_test.dart
test('a changed workspace root lock selects the tests of every member', () { /* ... */ });
test('the lock of a member is looked for at the workspace root', () { /* closure holds it only when in the snapshot */ });

// ac28_workspace_test.dart: AC-28 as written in testing.md
//   a member's file is analyzed with the root's package config; lockfile-out-of-sync reads the root lock;
//   a change in one member selects and runs the tests of another that imports it; `why` explains it.
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/dart-toolchain.md` section 2 and the decisions above.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(packages): support pub workspaces`

### Task 10: Documentation and 0.3.0

**Branch:** `docs/04-10-release`

**Files:**
- Modify: `README.md`, `action.yml`, `stagelatch.yaml`, `.github/workflows/ci.yaml` (dependencies the dogfood job needs for the packages whose tests it selects), `benchmark/README.md`, `docs/plans/README.md`, `docs/plans/04-affected.md` (tick the steps)
- Create: `benchmark/results/19-cli-0.3.0.json`
- Verify only (generated by Tasks 2 and 5): `docs/rules.md`

- [ ] **Step 1: Update the README.**
  - What it checks: rows for `tests/affected` (pre-push, ci) and `l10n/unused-key` (pre-commit, warning).
  - `tests/affected`: what is selected, the closure and the divergence rule in plain words, the skip warning and what it means (including a push of a branch that is not checked out), the list of documented limitations of ADR-0018 verbatim in substance (fixtures, goldens, assets, `dart_test.yaml`, `flutter_test_config.dart`, `pubspec_overrides.yaml`, `build.yaml`, gitignored files; generated code when `codegen.generated_files_committed` is `false`; a gitignored `pubspec.lock`), and that it never runs on commit.
  - **Fork pull requests (ADR-0018, S14):** `stagelatch ci` with `tests/affected` executes the pull request's tests and the code they import, like a `dart test` step; for pull requests from forks the usual restrictions on secrets apply, and workflows must use `pull_request`, never `pull_request_target`.
  - `why`, with the example of `cli.md` 3.8; workspaces; the cache: where it lives (`<git common dir>/stagelatch/cache`, that is `.git/stagelatch/cache` in a plain clone), that it is shared by linked worktrees, safe to delete at any time, with no eviction.
  - The SARIF upload snippet for code scanning, with `github/codeql-action/upload-sarif` pinned to a full commit SHA with the version in a comment (S8), using the new `output` input of the action; the JUnit reporter in a line.
  - Configuration example: `pre-push: [analyze, tests/affected]`.
- [ ] **Step 2: Update `action.yml`.** `reporter` accepts `console`, `json`, `github`, `junit` and `sarif`; a new optional `output` input writes the report to that path (the step redirects stdout, keeps the exit code, and passes the input through an environment variable like the others); a description line that `tests/affected` executes the pull request's tests.
- [ ] **Step 3: Measure** with `benchmark/bin/measure_cli.dart` on the corpus, with a warm and a cold facts cache (delete `.git/stagelatch/cache` of the corpus for cold), for the `pre-commit` default and for `pre-push` with `analyze` and `tests/affected` (the corpus has tests or the scenario adds one). Save `benchmark/results/19-cli-0.3.0.json`, add the rows to the README table and note the cache effect. The `l10n/unused-key` numbers of Task 2 stay published as measured.
- [ ] **Step 4: Dogfood.** Enable `tests/affected` in the `pre-push` list of this repository's `stagelatch.yaml` (ADR-0018) and update its comment. The `ci` list defaults to the union, so the dogfood job runs it. List the packages that own tests the job selects and make the job run `dart pub get` for each (today: the root, `benchmark`, `test/fixtures/dart_app`). Measure the job. If it takes longer than the slowest cell of the `test` matrix, **stop and ask the owner**: ADR-0018 allows an explicit `ci:` list without `tests/affected`, and that choice is the owner's.
- [ ] **Step 5: Verify** all four commands and `dart pub publish --dry-run`; `docs/rules.md` is current.
- [ ] **Step 6: Commit.** `docs: document 0.3.0`
- [ ] **Step 7: Release** `0.3.0` per `workflow.md` section 8. `0.2.0` plus a `feat` gives `0.3.0` on its own: no `release-as`. In the release pull request, set plan 04 to `done (0.3.0)` in `docs/plans/README.md`.

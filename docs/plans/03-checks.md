# Checks (0.2.0) Implementation Plan

> Revised on 2026-11-20 after ADR-0017 and the 0.1.0 code.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `0.2.0`: the rest of `pubspec`, `assets`, `l10n` (without `unused-key`), `codegen/stale`, `tests/solo`, `tests/new-skip`, the baseline, `--all` and the config JSON Schema.

**Architecture:** Every new rule is a pure function over domain ports. Two rules need new syntactic facts (`annotatedDeclarations`, `testCalls`), produced by a hand-written lexer and recognizers next to the 0.1.0 directive scanner ([ADR-0017](../adr/0017-hand-written-lexer-for-declaration-and-test-call-facts.md)). The baseline is one more filter at the end of the chain, reading its file from the snapshot.

**Tech Stack:** As plan 02, plus `crypto` (SHA-256 of token hashes and baseline fingerprints). It is already approved in the dependency table of `coding-standards.md`, and Task 5 is the first to declare it. No `analyzer`, no `dart_style`.

**Spec:** [`specs/rules.md`](../specs/rules.md) `pubspec`, `assets`, `l10n`, `codegen`, `tests`; [`specs/baseline-and-suppression.md`](../specs/baseline-and-suppression.md) 4; [`specs/dart-toolchain.md`](../specs/dart-toolchain.md) 6; [`specs/config.md`](../specs/config.md) 3 and 7; [`specs/cli.md`](../specs/cli.md) 3.4, 3.5, 3.7, 4, 5; [`specs/git.md`](../specs/git.md) 4.4.

## Order

Tasks run in this order: **1, 2, 3, 4, 5, 6, 8, 7, 9, 10.** Task 4 needs Task 1. Task 7 needs Task 8, because `baseline create` and `prune` use the public `--all` path. Tasks 5 and 6 both extend the fact extractor, so Task 6 stacks on Task 5. Tasks 1, 2, 3, 5 and 9 depend on nothing before them and may be stacked or run in parallel branches; two writers never touch the same file.

## Global Constraints

- Everything in plan 01's and plan 02's Global Constraints.
- New rules read content only through `SnapshotFiles`, `Documents` and `DartToolchain.facts`. No rule adds a port.
- Rules that compare with the base handle "no base" (first commit) and "file absent in the base" without special cases leaking into messages.
- Hand-written scanners are linear in the input, use no recursion that depends on it, and have an adversarial-input test (S6): 1 MiB of each hostile shape finishes, with no stack overflow.
- **Registering a check** (`cli/composition.dart`) appends it to the registry, which sets the order of the check table. The final order is `format`, `analyze`, `pubspec`, `sensitive-files`, `assets`, `l10n`, `codegen`, `tests`. A check that is in the default `pre-commit` list shows a row in every pre-commit report, so the task that registers one updates `cleanReport` and `blockedReport` in `test/support/acceptance.dart` and every golden or test that spells the check table, in the same PR.
- A check that needs the declarations or calls of a file skips a file whose facts are not `isWellFormed` and leaves it to `analyze` (ADR-0017). It never reads an empty list as "no declarations".
- The baseline file format is versioned; this plan writes `"version": 1`.
- `tests.functions` reaches the extractor through `DartToolchainFactory.create`, never through a new port (ADR-0017).
- A commit of this plan never carries `!` or a `BREAKING CHANGE:` footer (`workflow.md`, section 8).

## What 0.1.0 already has (verified against the code)

- `DartToolchain.facts(SnapshotFiles files, RepoPath path)` takes the snapshot explicitly, so a check reads the facts of the base through `CheckContext.base`. `LazyToolchain.facts` locates the SDK before creating the real toolchain; this is cheap (no process) and accepted: a facts-only run on a machine without a resolvable SDK fails like `format` does.
- There is no facts cache in `0.2.0` (the content-hash cache is plan 04). The cost is the lexer: about 1 ms per file, at most 6 and 20 file versions in the `s3` and `s10` scenarios (`spike/facts-report.md`).
- `ChangeSet` has `FileChange.previousPath` for renames; `PackageMap.packageOf(path)` finds the owning package.
- `RunRequest.all` and `ResolvedRun` are already plumbed through `Pipeline`; only `GitCliRepository.resolve` refuses `all`. `RunReport.baselined` exists and is printed by the console reporter, always 0.
- The filter chain is `applySelection`, `applyLevels`, `applyExclude` and `applyInlineIgnores`, applied per check inside `Pipeline`. The baseline must be applied after the global sort, so it is a separate step after the checks' findings are gathered (Task 7).
- `ConfigLoader` keeps each section's allowed keys inside its readers; nothing exposes them (Task 9 compares by behavior).

## Review Focus

- **An ARB message with quoted braces (`'{'`) or a doubled apostrophe.** Expected: not counted as a placeholder. Pinned in Task 1.
- **A `pubspec.lock` entry from git, path or the SDK.** Expected: source kinds are compared; version constraints are checked only for hosted packages. Pinned in Task 2.
- **An asset directory declared with only resolution-variant subdirectories below it.** Expected: variants count as declared; the directory is not "missing". Pinned in Task 3.
- **A test whose description is built by interpolation or a variable.** Expected: its key falls back to the source text; no crash, no false "new skip" when nothing changed. Pinned in Task 6.
- **A baselined file that is later renamed.** Expected: its findings reappear as new (documented), and `baseline prune` drops the stale entries. Pinned in Task 7.
- **A file the lexer cannot read** (an unterminated string or unpaired brackets). Expected: no `codegen` or `tests` finding for it; `analyze` reports the syntax error. Pinned in Tasks 5 and 6.
- **A source file renamed together with its generated part.** Expected: compared with its previous path in the base; the renamed part counts as in the changeset. Pinned in Task 5.
- **Two identical findings in one run, and entries consumed in sorted order across checks.** Expected: counts are consumed in the pipeline's global sort order, not check by check. Pinned in Task 7.
- **`--all` on a repository with no commit yet.** Expected: every index file is `added`, the base is null, no crash. Pinned in Task 8.
- **A hostile 1 MiB file** in the facts path. Expected: linear time, no stack overflow. Pinned in Tasks 1, 5 and 6.

---

### Task 1: ICU placeholder scanner

**Branch:** `feat/03-01-icu-scanner`

**Files:**
- Create: `lib/src/checks/l10n/icu_arguments.dart`
- Test: `test/checks/l10n/icu_arguments_test.dart`

**Interfaces:**
- Produces: `Set<String> icuArguments(String message)`. Never throws.

- [x] **Step 1: Write the failing tests.**

```dart
test('simple, plural and select arguments, including nested ones', () {
  expect(icuArguments('Hi {name}'), {'name'});
  expect(icuArguments('{count, plural, =0{none} other{{count} items for {user}}}'), {'count', 'user'});
  expect(icuArguments('{gender, select, male{He} other{They}} liked {thing}'), {'gender', 'thing'});
});
test('quoted text is literal', () {
  expect(icuArguments("Use '{name}' literally"), isEmpty);
  expect(icuArguments("It''s {name}"), {'name'});
});
test('plural keywords and literal branches are not arguments', () {
  expect(icuArguments('{n, plural, one{one} other{many}}'), {'n'});
});
test('unbalanced input returns what was found and never throws', () {
  expect(icuArguments('{name'), {'name'}); expect(icuArguments('}}{{'), isEmpty);
});
test('deep nesting and a very long message complete', () { /* 10,000 nested braces; 1 MiB message; 1 MiB of "{" and of "{a, plural, " */ });
```

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement** as a single left-to-right scan with an explicit stack (no recursion, so depth cannot overflow the call stack).
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(checks): add ICU argument scanner`

### Task 2: Remaining `pubspec` rules

**Branch:** `feat/03-02-pubspec-rules`

**Files:**
- Create: `lib/src/checks/pubspec/unpinned_git.dart`, `build_number_regression.dart`, `lockfile_out_of_sync.dart`, `lockfile_document.dart`
- Modify: `lib/src/checks/pubspec/pubspec_check.dart`, `pubspec_document.dart`
- Test: one file per rule under `test/checks/pubspec/`

**Interfaces:**
- Consumes: `PubspecDocument`, `PubspecSettings`, `CheckContext.targetBranch`, `CheckContext.base`.
- Produces: `unpinnedGitFindings(PubspecDocument, RepoPath, {required bool requireSha})`; `buildNumberRegressionFindings({required PubspecDocument snapshot, required PubspecDocument? base, required RepoPath path})`; `lockfileFindings({required PubspecDocument pubspec, required LockfileDocument lock, required RepoPath pubspecPath})`; `LockfileDocument` exposing `Map<String, LockedPackage>` with `version`, `source` (`hosted`, `git`, `path`, `sdk`) and `dependencyKind`.

- [x] **Step 1: Write the failing tests.** Messages are asserted exactly as in `specs/rules.md`.

```dart
test('git dependency without ref', () { expect(f.single.message, 'Git dependency "ui" has no ref.'); });
test('short form (git: url) has no ref', () { /* git: https://... */ });
test('require_sha rejects branch and tag refs and accepts 40 hex characters', () {
  expect(f.single.message, 'Git dependency "ui" must be pinned to a full commit SHA, found "main".');
});
test('version going backwards', () {
  expect(regress('1.2.0+10', '1.1.9+11').single.message, 'Version went backwards: 1.2.0+10 -> 1.1.9+11.');
  expect(regress('1.2.0+10', '1.2.0+9'), hasLength(1));
  expect(regress('1.2.0+10', '1.2.0'), hasLength(1));
  expect(regress('1.2.0+9', '1.2.0+10'), isEmpty);       // numeric, not lexical
  expect(regress('1.2.0+10', '1.2.0+10'), isEmpty);
  expect(regress('1.2.0+10', '1.3.0+1'), isEmpty);
});
test('the rule applies only when the target branch matches a configured glob', () async { /* release/1.2 vs main */ });
test('no base, or no version in the base, is not a regression', () async { /* ... */ });
test('lock does not satisfy a hosted constraint', () {
  expect(f.single.message, 'pubspec.lock does not satisfy "http": locked 0.13.6, required ^1.2.0.');
});
test('dependency missing from the lock', () { expect(f.single.message, '"http" is missing from pubspec.lock.'); });
test('source kind differs', () { expect(f.single.message, 'pubspec.lock resolves "ui" from hosted, but pubspec.yaml declares path.'); });
test('a direct lock entry the pubspec does not declare', () { expect(f.single.location.start, const Position(1, 1)); });
test('git, path and sdk dependencies are compared by source only', () { /* ... */ });
test('"any" and an omitted constraint accept every version', () { /* ... */ });
test('no sibling pubspec.lock in the snapshot means the rule is silent', () async { /* ... */ });
```

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement.** Version and constraint parsing use `package:pub_semver`; an unparseable constraint is skipped, not an error.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(checks): add unpinned-git, build-number-regression and lockfile-out-of-sync`

### Task 3: The `assets` check

**Branch:** `feat/03-03-assets`

**Files:**
- Create: `lib/src/checks/assets/assets_check.dart`, `asset_declarations.dart`, `format_size.dart`
- Modify: `lib/src/cli/composition.dart` (register `AssetsCheck`), `test/support/acceptance.dart`
- Test: `test/checks/assets/asset_declarations_test.dart`, `assets_check_test.dart`, `format_size_test.dart`

**Interfaces:**
- Produces: `AssetsCheck implements Check` (`id: 'assets'`; rules `missing`, `undeclared`, `max-file-size`); `AssetDeclarations.fromPubspec(PubspecDocument, RepoPath pubspecPath)` with `bool declares(RepoPath file)` and `Iterable<DeclaredAsset> get entries`; `String formatSize(int bytes, {required int limit})`.

- [x] **Step 1: Write the failing tests.**

```dart
test('a file is declared by exact path or by its directory, not recursively', () {
  final d = declarations(['assets/img/', 'assets/data/config.json']);
  expect(d.declares(RepoPath('assets/img/a.png')), isTrue);
  expect(d.declares(RepoPath('assets/img/icons/b.png')), isFalse);
  expect(d.declares(RepoPath('assets/data/config.json')), isTrue);
});
test('resolution variants are covered by their parent', () {
  expect(declarations(['assets/img/']).declares(RepoPath('assets/img/2.0x/a.png')), isTrue);
  expect(declarations(['assets/img/a.png']).declares(RepoPath('assets/img/3.0x/a.png')), isTrue);
});
test('fonts listed under flutter: fonts are declared', () { /* ... */ });
test('declared file absent from the snapshot', () async {
  expect(f.single.message, 'Asset "assets/img/logo.png" is declared but does not exist.');
});
test('declared directory that only has variant subdirectories is not missing', () async { /* ... */ });
test('changed file under a root that is not declared', () async {
  expect(f.single.message, 'File is under "assets/" but is not declared in pubspec.yaml.');
});
test('file over the limit', () async { expect(f.single.message, 'File is 612.4KB, larger than the limit of 500KB.'); });
test('assets.ignore exempts a path from all three rules', () async { /* ... */ });
test('paths are resolved relative to the package of the pubspec', () async { /* packages/ui/assets/ */ });
test('deleting an asset triggers the missing rule for its declaration', () async { /* ... */ });
```

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement.** A variant directory name matches a digit run, an optional `.digits`, then `x`. Sizes come from `SnapshotFiles.size`, never from reading content. Register `AssetsCheck` and update the check table in `cleanReport`, `blockedReport` and the goldens that spell it.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(checks): add assets check`

### Task 4: The `l10n` check

**Branch:** `feat/03-04-l10n`

**Files:**
- Create: `lib/src/checks/l10n/l10n_check.dart`, `l10n_setup.dart`, `arb_document.dart`
- Modify: `lib/src/cli/composition.dart` (register `L10nCheck`), `test/support/acceptance.dart`
- Test: `test/checks/l10n/l10n_setup_test.dart`, `l10n_check_test.dart`

**Interfaces:**
- Consumes: `icuArguments`, `Documents.json`, `Documents.yaml`.
- Produces: `L10nCheck implements Check` (`id: 'l10n'`; rules `missing-key`, `placeholder-mismatch`, `unparseable`; `unused-key` is registered in plan 04, not before); `L10nSetup { RepoPath arbDir; String templateFile; RepoPath? outputDir }` from `Future<L10nSetup?> readL10nSetup(SnapshotFiles, Documents, DartPackage)`; `ArbDocument` with `Map<String, LocatedEntry> get messages` (keys not starting with `@`).

- [x] **Step 1: Write the failing tests.**

```dart
test('defaults are lib/l10n and app_en.arb; l10n.yaml overrides them', () async { /* ... */ });
test('a package without l10n.yaml is skipped', () async { /* ... */ });
test('key missing in a translation, located at the template key', () async {
  expect(f.single.message, 'Key "checkoutTitle" is missing in app_pt.arb.');
  expect(f.single.location.path, RepoPath('lib/l10n/app_en.arb'));
});
test('placeholder sets differ', () async {
  expect(f.single.message, 'Placeholders of "greeting" differ from the template: expected {count, name}, found {name}.');
  expect(f.single.location.path, RepoPath('lib/l10n/app_pt.arb'));
});
test('metadata keys (@key, @@locale) are not messages', () async { /* ... */ });
test('a non-string message value is ignored by the placeholder rule', () async { /* ... */ });
test('invalid JSON yields l10n/unparseable and the file is skipped by the other rules', () async {
  expect(f.single.message, startsWith('app_pt.arb is not valid JSON: '));
});
test('the check runs when any ARB of the directory or l10n.yaml changed, and compares all locales', () async { /* ... */ });
test('extra keys in a translation are not reported', () async { /* ... */ });
```

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement** per `specs/rules.md` `l10n`. Register `L10nCheck` and update the check table in `cleanReport`, `blockedReport` and the goldens that spell it.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(checks): add l10n missing-key and placeholder-mismatch`

### Task 5: Annotated-declaration facts and `codegen/stale`

**Branch:** `feat/03-05-codegen-stale`

**Files:**
- Create: `lib/src/infrastructure/dart/dart_lexer.dart`, `declaration_facts.dart`; `lib/src/checks/codegen/codegen_check.dart`, `codegen_signature.dart`
- Modify: `lib/src/domain/dart/dart_file_facts.dart` (`isWellFormed`), `lib/src/infrastructure/dart/syntactic_facts.dart`, `pubspec.yaml` (declare `crypto: ^3.0.8`), `lib/src/cli/composition.dart` (register `CodegenCheck`), `test/support/acceptance.dart`, `docs/architecture.md`
- Test: `test/infrastructure/dart/dart_lexer_test.dart`, `declaration_facts_test.dart`, `facts_adversarial_test.dart`, `test/checks/codegen/codegen_signature_test.dart`, `codegen_check_test.dart`

**Interfaces:**
- Consumes: `DartToolchain.facts`, `CodegenSettings`, `CheckContext.base`, `CheckContext.changes`.
- Produces:
  - `DartFileFacts.isWellFormed` (default `true`); `SyntacticFacts.extract` fills `annotatedDeclarations` and sets `isWellFormed` per ADR-0017, keeping the 0.1.0 `directives` unchanged.
  - `Lexed lex(String source)` in `dart_lexer.dart` (tokens as parallel lists, `match` for brackets, `balanced`); promoted from `benchmark/lib/facts_scanner.dart`, which stays the reference prototype until Task 6 re-points `benchmark/` at it.
  - `CodegenCheck implements Check` (`id: 'codegen'`, phase verify; rule `stale`).
  - `CodegenSignature.of(DartFileFacts facts, List<String> suffixes)` with `List<String> generatedParts` and `SignatureDifference? firstDifference(CodegenSignature? base)`; `SignatureDifference { String declaration; Location? location }`.

**Decisions fixed here** (the spec leaves them open; they are added to `specs/rules.md`):
- A **source file** is a changed (not deleted) `.dart` file with `isWellFormed` and at least one relative `part` URI ending in a configured suffix. Its generated part is the file that URI names, next to the source.
- The base side is `change.previousPath ?? change.path` read from `CheckContext.base`. With no base, the file absent in the base, or base facts that are not well formed, the base signature is null: the file counts as new.
- A **finding per generated part** that is missing from the changeset while the signature differs. A part that is absent from the snapshot yields `is declared as a part but is missing.` instead, and not the stale message for that part.
- `<declaration>` is the first differing annotated declaration (by name; entries compared by annotations and token hash). If a declaration was only removed, its name is used and the location is the first `part` directive; if only the part list differs, `<declaration>` is the source file's name and the location is the `part` directive.
- Annotation names, the ignored set and the naming of members and enum constants are those of `specs/dart-toolchain.md` section 6.

- [x] **Step 1: Write the failing tests.**

```dart
// dart_lexer_test.dart: tokens and lexemes
test('strings with nested interpolation lex like the Dart scanner', () { /* r'...', '''...''', ${a + '${b}'} */ });
test('numbers with digit separators, hex, exponents; [] and []= are single tokens', () { /* ... */ });
test('unterminated string, unterminated block comment and unpaired brackets set balanced to false', () { /* ... */ });
// declaration_facts_test.dart
test('token hash ignores whitespace and comments', () {
  expect(hashOf('@JsonSerializable()\nclass A { final int x; A(this.x); }'),
         hashOf('@JsonSerializable()\nclass A {\n  // note\n  final int x;\n  A(this.x);\n}'));
});
test('token hash changes when a field is added', () { /* ... */ });
test('annotations are names without arguments, sorted; excluded annotations do not count', () {
  expect(decl.annotations, ['JsonSerializable', 'immutableRecord']);   // @override, @Deprecated(...) alone: no entry
});
test('annotated members are named Class.member; constructors Class.named or Class.new; enum constants Enum.value', () { /* ... */ });
test('methods with type parameters are found by their name', () { /* TResult map<TResult extends Object?>(...) */ });
test('a constructor initializer list with brace literals ends at its body', () { /* A(this.x) : y = {1: 2} {} */ });
test('a file the lexer cannot read has isWellFormed false and no declarations', () { /* ... */ });
// facts_adversarial_test.dart (S6)
test('every hostile shape of 1 MiB finishes without overflowing the stack', () { /* (, {, [, nested ${, /*, unterminated string, one identifier, @a, class A { @a int x; */ });
// codegen_check_test.dart
test('annotated class changed, generated part not in the changeset', () async {
  expect(f.single.message, '"Order" changed but order.g.dart was not updated in this change.');
});
test('same change with the generated part in the changeset passes', () async { /* ... */ });
test('only non-annotated code changed: no finding', () async { /* ... */ });
test('new source file whose generated part is absent', () async {
  expect(f.single.message, 'order.g.dart is declared as a part but is missing.');
});
test('renamed source file is compared with its previous path in the base', () async { /* ... */ });
test('a part that is not a configured suffix does not make a source file', () async { /* ... */ });
test('two generated parts: only the one missing from the changeset is reported', () async { /* ... */ });
test('a removed annotated declaration is reported at the part directive', () async { /* ... */ });
test('generated_files_committed: false disables the check', () async { /* ... */ });
test('a file whose facts are not well formed is left to analyze', () async { /* isWellFormed false: no finding */ });
test('custom generated_suffixes are honored', () async { /* .config.dart */ });
test('no base (first commit) treats the file as new', () async { /* ... */ });
```

- [x] **Step 2: Run.** Expected: FAIL (`dart_lexer.dart` and `CodegenCheck` do not exist; `isWellFormed` is not a getter).
- [x] **Step 3: Implement** per `specs/rules.md` `codegen`, `specs/dart-toolchain.md` section 6 and ADR-0017. Start from the prototype in `benchmark/lib/facts_scanner.dart`; replace its throwaway shapes with `AnnotatedDeclaration` and `Location`, and compute the hash with `package:crypto` over the lexemes joined by one space. The lexer uses an explicit bracket stack and no recursion. Add the failing adversarial test before the hostile inputs are handled. Register `CodegenCheck` in `composition.dart` after the checks that exist, and update `cleanReport`, `blockedReport` and the goldens that spell the check table.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(checks): add codegen/stale from annotated-declaration facts`

### Task 6: Test-call facts, `tests/solo` and `tests/new-skip`

**Branch:** `feat/03-06-tests-rules` (stacked on Task 5)

**Files:**
- Create: `lib/src/infrastructure/dart/test_call_facts.dart`; `lib/src/checks/tests/tests_check.dart`, `test_key.dart`
- Modify: `lib/src/infrastructure/dart/syntactic_facts.dart` (constructor takes `testFunctions`), `lib/src/infrastructure/dart/sdk_dart_toolchain.dart` (the factory passes the set on), `lib/src/application/ports/dart_toolchain_factory.dart` (`create` gains `required Set<String> testFunctions`), `lib/src/application/pipeline/lazy_toolchain.dart` and `pipeline.dart` (pass `config.settings<TestsSettings>().functions`), `test/support/fake_dart_toolchain_factory.dart`, `lib/src/cli/composition.dart` (register `TestsCheck`), `test/support/acceptance.dart`, `test/acceptance/determinism_test.dart`, `benchmark/pubspec.yaml`, `benchmark/bin/facts.dart`, `docs/architecture.md`
- Delete: `benchmark/lib/facts_scanner.dart` (the shipped extractor replaces it)
- Test: `test/infrastructure/dart/test_calls_test.dart`, `test/checks/tests/test_key_test.dart`, `tests_check_test.dart`

**Interfaces:**
- Consumes: `DartFileFacts.testCalls`, `isWellFormed`, `TestsSettings.functions`, `CheckContext.base`, `PackageMap`.
- Produces: `SyntacticFacts({Set<String> testFunctions})` filling `testCalls` and `TestCall.skip` for `skip:` and `@Skip`; `DartToolchainFactory.create(..., testFunctions)`; `TestsCheck implements Check` (`id: 'tests'`; rules `solo`, `new-skip`; `affected` is registered in plan 04, not before); `String testKey(TestCall call)`; `bool isTestFile(RepoPath path, PackageMap packages)`.

**Decisions fixed here:**
- `group` is the function that opens a group; `groups` lists the enclosing `group` descriptions. A `group` call is itself a test call (so `group('x', ..., skip: true)` is a skip for "x").
- A call has `skip` set by its own `skip:` argument (not `false`, not `null`), else by a `@Skip` annotation on the enclosing top-level function, else by a `@Skip` annotation on the library. The location is the argument or the annotation.
- A call is unqualified: not `obj.test(...)`, not a cascade; and has at least one positional argument.
- The key of a call is `[...groups, description]`; a non-literal description is its source text.
- `tests/new-skip`: for each key, the snapshot's skipped calls minus the base's skipped calls (multiset). If the snapshot has more skipped calls of a key than the base, the **later** ones in source order are reported. The base is `change.previousPath ?? change.path`; no base or an unreadable base file means every skip is new. A file that is not well formed is skipped.
- A **test file** is a `.dart` file under `test/` of its package, at any depth, whose name ends with `_test.dart`.

- [x] **Step 1: Write the failing tests.**

```dart
// test_calls_test.dart
test('calls are collected with their enclosing groups', () {
  final c = calls("group('cart', () { test('adds', () {}, skip: true); });").last;
  expect(c.groups, ['cart']); expect(c.description, 'adds'); expect(c.skip, isNotNull); expect(c.solo, isNull);
});
test('solo: false and skip: false or null are not set', () { /* ... */ });
test('a @Skip annotation on the library or on the enclosing function counts as skip', () { /* ... */ });
test('a non-literal description uses its source text', () { expect(c.description, r"'adds $n'"); });
test('escapes, raw strings, adjacent literals and multi-line literals give the literal value', () { /* ... */ });
test('only functions named in tests.functions are collected; obj.test() and a declaration are not calls', () { /* testGoldens ignored by default */ });
test('a hostile 1 MiB of test( or group( finishes', () { /* S6 */ });
// tests_check_test.dart
test('solo in a changed test file is reported at the argument', () async {
  expect(f.single.message, '"solo" must not be committed: it silently skips every other test.');
});
test('a skip that exists in the base is not reported', () async { /* ... */ });
test('a skip added to an existing test is reported as a warning', () async {
  expect(f.single.message, 'Test "adds" was skipped in this change.'); expect(f.single.severity, Severity.warning);
});
test('a new test that is born skipped is reported', () async { /* ... */ });
test('two tests with the same key: only the additional skip is reported', () async { /* base has one skipped, snapshot has two */ });
test('a file outside test/ or not ending in _test.dart is not a test file', () async { /* ... */ });
test('a new file has no base: every skip is new', () async { /* ... */ });
test('a renamed test file is compared with its previous path', () async { /* ... */ });
test('a file that is not well formed is left to analyze', () async { /* ... */ });
```

The determinism scenario gains a staged test file with a `solo: true`, so the byte-identical comparison exercises a new check.

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement.** New skips are found by multiset difference of skipped keys, snapshot minus base. Re-point `benchmark/` at the shipped code: add `stagelatch: {path: ..}` to `benchmark/pubspec.yaml`, change `bin/facts.dart` to import the extractor from `package:stagelatch`, delete `benchmark/lib/facts_scanner.dart`, and run `dart run bin/facts.dart compare` and `edges` against the corpus; record the result in the PR. If the path dependency cannot be resolved, say so under "Deviations" and keep the prototype.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(checks): add tests/solo and tests/new-skip`

### Task 8: `--all`

**Branch:** `feat/03-08-all-flag`

**Files:**
- Modify: `lib/src/infrastructure/git/git_cli_repository.dart`, `lib/src/cli/commands/run_command.dart`, `ci_command.dart`, `lib/src/application/pipeline/run_report.dart` (`RunReport.all`), `pipeline.dart`, `lib/src/infrastructure/reporters/console_reporter.dart`, `json_reporter.dart`, `docs/specs/cli.md`, `docs/architecture.md`, the reporter goldens under `test/goldens/`
- Test: `test/infrastructure/git/resolve_all_test.dart`, `test/cli/all_flag_test.dart`; adjust `test/cli/reporter_option_test.dart` and `test/cli/ci_command_test.dart` (they assert "--all is still a usage error")

**Interfaces:**
- Produces: `GitRepository.resolve(entry, all: true)` returning, for each run, a changeset that lists every regular file of the snapshot as `added` (symlinks and gitlinks excluded) with the base resolved as without `--all`; `RunReport.all`.

**Decisions fixed here** (written into `specs/cli.md` sections 4 and 5 and `specs/git.md` 4.4):
- Console header with `--all`: `stagelatch <entry>: all <n> file(s)`. Without it, unchanged.
- JSON: a boolean `"all"` right after `"files"`, always present. This is additive, so `schemaVersion` stays 1.
- `--all` applies to every entry point: the index for `pre-commit`, each pushed commit for `pre-push`, `HEAD` for `ci`. On a repository with no commit, the base is null.

- [x] **Step 1: Write the failing tests.**

```dart
test('all lists every regular file of the snapshot as added', () async { /* symlinks and gitlinks excluded */ });
test('the base snapshot is still available to rules', () async { expect(run.base, isNotNull); });
test('--all on a repository with no commit lists the index and has no base', () async { /* ... */ });
test('run pre-commit --all reports a violation in an unchanged file', () async { /* ... */ });
test('the console header reads "all <n> files"', () async { expect(out.toString(), startsWith('stagelatch pre-commit: all 3 files\n')); });
test('the JSON report has "all": true after "files", and false otherwise', () async { /* ... */ });
test('ci --all and run pre-push --all resolve every file of their snapshot', () async { /* ... */ });
```

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement.** Remove the three "arrives in 0.2.0" markers (`run_command.dart:61`, `ci_command.dart:53`, `git_cli_repository.dart:102`). List files with `git ls-tree -r -z` (commit snapshots) or `git ls-files -s -z` (index), skipping modes `120000` and `160000`.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(cli): add --all to run and ci`

### Task 7: Baseline

**Branch:** `feat/03-07-baseline` (after Task 8)

**Files:**
- Create: `lib/src/application/baseline/fingerprint.dart`, `baseline.dart`, `baseline_codec.dart`, `baseline_filter.dart`, `baseline_commands.dart`; `lib/src/cli/commands/baseline_command.dart`
- Modify: `lib/src/application/pipeline/pipeline.dart`, `run_report.dart` (`RunRequest.hook`, `RunRequest.useBaseline`), `lib/src/cli/composition.dart` and `runner.dart` (register the command), `docs/specs/baseline-and-suppression.md`, `docs/architecture.md`
- Test: `test/application/baseline/*_test.dart`, `test/application/pipeline/baseline_order_test.dart`, `test/cli/baseline_command_test.dart`, `test/acceptance/ac23_baseline_test.dart`

**Interfaces:**
- Consumes: `Pipeline.run`, `RunRequest.all` (Task 8), `SnapshotFiles`, `WorkingTree`, `Config.baselinePath`, `package:crypto`.
- Produces: `String normalizeSnippet(List<String> lines)`; `Future<String> fingerprintOf(Finding finding, SnapshotFiles snapshot)`; `BaselineEntry { RuleId rule; RepoPath path; String fingerprint; int count }`; `Baseline(List<BaselineEntry> entries)` with `Baseline.empty`; `Baseline decodeBaseline(String json)` throwing `ConfigException`; `String encodeBaseline(Baseline)`; `Future<BaselineOutcome> applyBaseline(List<Finding>, Baseline, SnapshotFiles)` with `kept` and `baselined`; `RunRequest({..., String? hook, bool useBaseline = true})`; `BaselineCommands(Pipeline, WorkingTree)` with `create({required bool force})` and `prune()` returning the message to print.

**Decisions fixed here** (added to `specs/baseline-and-suppression.md` section 4):
- **Where the filter sits.** After every check's findings are filtered by selection, levels, exclude and inline ignores, **sorted globally** with `Finding.compare`, then the baseline consumes counts in that order, then `stagelatch/invalid-ignore` findings are added and the list is sorted again. So consumption order is the global sort order, never per check.
- **Reading.** The pipeline reads the baseline from the run's snapshot through `SnapshotFiles.readText(config.baselinePath)`: a missing file is `Baseline.empty`; invalid JSON, an unknown `version` or a malformed entry throws `ConfigException` with the baseline path (exit 78).
- **`create` and `prune`.** Their run is `RunRequest(entry: PreCommitEntry, all: true, allowFixes: false, hook: 'ci', useBaseline: false)`: the index, every file, the selectors of `hooks.ci` and no baseline. `create` refuses to overwrite when the working-tree file exists; `prune` reads the working-tree file, because it is the one the developer is editing. Both write through `WorkingTree.writeText` to `Config.baselinePath`, which is a `RepoPath` and so cannot leave the repository.
- A path-based finding on a file with no text (binary) has an empty snippet; the fingerprint then depends on rule and path only.

- [x] **Step 1: Write the failing tests.**

```dart
test('normalization trims, collapses inner whitespace and joins lines', () {
  expect(normalizeSnippet(['  import   "a.dart";\t', '  x  ']), 'import "a.dart"; x');
});
test('the fingerprint does not depend on the line number', () async {
  expect(await fingerprintOf(findingAtLine(3), before), await fingerprintOf(findingAtLine(9), afterInsertingSixLines));
});
test('the fingerprint depends on rule, path and snippet', () async { /* three pairwise differences */ });
test('a non-text file has an empty snippet', () async { /* sensitive-files finding on a binary */ });
test('encode sorts entries and is stable; decode(encode(x)) == x', () { /* golden baseline.json */ });
test('malformed baseline is a config error', () { /* invalid JSON; version 2; missing field */ });
test('counts are consumed in finding order', () async {
  // three identical findings, entry count 2
  expect(outcome.kept, hasLength(1)); expect(outcome.baselined, 2);
});
test('counts are consumed in the global sort order across checks', () async { /* two checks, same path */ });
test('invalid-ignore findings are never baselined', () async { /* ... */ });
test('create writes all current findings and refuses to overwrite', () async {
  expect(message, 'Wrote 3 entries to .stagelatch/baseline.json. Stage it to take effect.');
});
test('create refuses with the documented message when the file exists', () async { /* exit 64 */ });
test('prune lowers counts and removes stale entries, and never adds', () async {
  expect(message, 'Removed 2 stale entries; 1 remain.');
});
test('prune without a baseline file says so and succeeds', () async { /* No baseline at <path>. */ });
test('the baseline is read from the snapshot, not the working tree', () async { /* ADR-0015 */ });
test('the report counts baselined findings in the console summary and the JSON', () async { /* "(0 suppressed, 2 baselined)" */ });
```

AC-23 (`test/acceptance/ac23_baseline_test.dart`, pattern of `ac22_*`, helper `test/support/acceptance.dart`): a legacy violation is baselined and staged: commit passes. A second, new violation in the same file: commit blocked, only the new one reported. Insert lines above the old violation: still baselined. Rename the file: the old violation is reported again; `baseline prune` drops the stale entry. It uses `pubspec/path-dependency`, which exists since `0.1.0`.

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement** per `specs/baseline-and-suppression.md` section 4 and the decisions above.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(baseline): add fingerprinted baseline with create and prune`

### Task 9: Config JSON Schema

**Branch:** `feat/03-09-json-schema`

**Files:**
- Create: `schema/stagelatch.schema.json`
- Test: `test/application/config/schema_agreement_test.dart`

The loader keeps each section's allowed keys inside its readers and does not expose them. The test therefore compares by behavior and against the spec, and Task 9 does not change `config_loader.dart`.

- [x] **Step 1: Write the failing test.**

```dart
test('every key of the schema is accepted by the loader, at its place, with a value from the schema\'s examples', () async {
  // for each property path in the schema, build a one-key config from its first example and load it: no ConfigException
});
test('the loader rejects an unknown key at the root and in every section, as the schema does', () async { /* additionalProperties: false */ });
test('the schema keys equal the keys of the table in specs/config.md section 3', () { /* parse the table */ });
test('the schema is draft 2020-12 with additionalProperties: false at every object, and a description on every property', () { /* ... */ });
test('enumerations match: levels, scopes, fail_on values, hook names', () { /* ... */ });
test('rules accepts only names matching the rule id pattern', () { /* patternProperties */ });
```

- [x] **Step 2: Run.** Expected: FAIL, file missing.
- [x] **Step 3: Write the schema** by hand from `specs/config.md` section 3, with a `description` and an `examples` entry per key. `rules` is an object whose property names match the rule ID pattern.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(config): publish JSON Schema for stagelatch.yaml`

### Task 10: `init` detection, documentation and 0.2.0

**Branch:** `docs/03-10-release`

**Files:**
- Modify: `lib/src/application/init/config_writer.dart`, `README.md`, `stagelatch.yaml`, `docs/README.md`, `docs/plans/README.md`
- Create: `docs/rules.md` (the user-facing rule reference), `tool/generate_rules_doc.dart` (writes it from the registry's `RuleDescriptor`s)
- Test: `test/application/init/config_writer_test.dart`, `test/docs/rules_reference_test.dart`, `test/docs/readme_test.dart` if the README carries generated numbers

**Notes:**
- `default_hooks.dart` already lists `codegen`, `l10n`, `assets`, `tests/solo` and `tests/new-skip` in the pre-commit default and filters by the catalog, so registering the checks (Tasks 3 to 6) is what changes what `init` writes. `ProjectDetector` already detects `usesCodegen`, `usesL10n` and `usesAssets` (PR #16). This task adds the tests below, not new detection.
- `docs/` is not published (`.pubignore`), so the README links `docs/rules.md` by its GitHub URL.
- `docs/rules.md` is generated; the test regenerates the text from the registry and compares it with the file, and the generator's command is in the file's first lines.

- [x] **Step 1: Write the failing tests.**

```dart
test('init lists codegen only when build_runner is a dev dependency', () { /* ... */ });
test('init lists l10n only when l10n.yaml exists, and assets only when the pubspec declares assets', () { /* ... */ });
test('init always lists tests/solo and tests/new-skip in pre-commit and never tests/affected', () { /* ... */ });
test('init adds the yaml-language-server schema comment as the first line', () {
  expect(text, startsWith('# yaml-language-server: \$schema=https://raw.githubusercontent.com/danielcbdev/stagelatch/main/schema/stagelatch.schema.json\n'));
});
test('docs/rules.md equals what the generator writes from the registry, and lists every registered rule exactly once', () { /* ... */ });
```

- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement,** then update the README: the new rules, `--all`, a baseline adoption guide (`baseline create`, review the file, stage it, `baseline prune`), and the new `pre-commit` measurement for the `s3` and `s10` scenarios, hot and cold, with the exact command (`benchmark/bin/measure_cli.dart`) and the 0.1.0 numbers beside it. The measurement must stay under 2 s; if it does not, stop and ask (a new check must not be weakened silently).
- [x] **Step 4: Run** all four commands; `dart pub publish --dry-run` is clean.
- [x] **Step 5: Commit.** `docs: document 0.2.0 rules and baseline adoption`
- [ ] **Step 6: Release** `0.2.0` per `workflow.md` section 8. No `release-as` is needed: from `0.1.0` a `feat` bumps to `0.2.0`, and no commit of this plan may carry a breaking marker. Open the pull request from `release/0.2.0` into `main` titled `release: 0.2.0`, with plan 03 marked `done (0.2.0)` in `docs/plans/README.md`. The owner merges it, and the release-please steps of section 8 follow.

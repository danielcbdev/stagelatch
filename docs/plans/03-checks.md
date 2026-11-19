# Checks (0.2.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `0.2.0`: the rest of `pubspec`, `assets`, `l10n` (without `unused-key`), `codegen/stale`, `tests/solo`, `tests/new-skip`, the baseline, `--all` and the config JSON Schema.

**Architecture:** Every new rule is a pure function over domain ports. Two rules need new syntactic facts (`annotatedDeclarations`, `testCalls`), added to the existing extractor. The baseline is one more filter at the end of the chain, reading its file from the snapshot.

**Tech Stack:** As plan 02. No new runtime dependency.

**Spec:** [`specs/rules.md`](../specs/rules.md) `pubspec`, `assets`, `l10n`, `codegen`, `tests`; [`specs/baseline-and-suppression.md`](../specs/baseline-and-suppression.md) 4; [`specs/dart-toolchain.md`](../specs/dart-toolchain.md) 6; [`specs/config.md`](../specs/config.md) 7.

## Global Constraints

- Everything in plan 01's and plan 02's Global Constraints.
- New rules read content only through `SnapshotFiles`, `Documents` and `DartToolchain.facts`. No rule adds a port.
- Rules that compare with the base handle "no base" (first commit) and "file absent in the base" without special cases leaking into messages.
- Hand-written scanners are bounded by input length and have an adversarial-input test (S6).
- The baseline file format is versioned; this plan writes `"version": 1`.

## Review Focus

- **An ARB message with quoted braces (`'{'`) or a doubled apostrophe.** Expected: not counted as a placeholder. Pinned in Task 1.
- **A `pubspec.lock` entry from git, path or the SDK.** Expected: source kinds are compared; version constraints are checked only for hosted packages. Pinned in Task 2.
- **An asset directory declared with only resolution-variant subdirectories below it.** Expected: variants count as declared; the directory is not "missing". Pinned in Task 3.
- **A test whose description is built by interpolation or a variable.** Expected: its key falls back to the source text; no crash, no false "new skip" when nothing changed. Pinned in Task 6.
- **A baselined file that is later renamed.** Expected: its findings reappear as new (documented), and `baseline prune` removes the stale entries. Pinned in Task 7.

---

### Task 1: ICU placeholder scanner

**Branch:** `feat/03-01-icu-scanner`

**Files:**
- Create: `lib/src/checks/l10n/icu_arguments.dart`
- Test: `test/checks/l10n/icu_arguments_test.dart`

**Interfaces:**
- Produces: `Set<String> icuArguments(String message)`. Never throws.

- [ ] **Step 1: Write the failing tests.**

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
test('deep nesting and a very long message complete', () { /* 10,000 nested braces; 1 MiB message */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** as a single left-to-right scan with an explicit stack (no recursion, so depth cannot overflow the call stack).
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add ICU argument scanner`

### Task 2: Remaining `pubspec` rules

**Branch:** `feat/03-02-pubspec-rules`

**Files:**
- Create: `lib/src/checks/pubspec/unpinned_git.dart`, `build_number_regression.dart`, `lockfile_out_of_sync.dart`, `lockfile_document.dart`
- Modify: `lib/src/checks/pubspec/pubspec_check.dart`, `pubspec_document.dart`
- Test: one file per rule under `test/checks/pubspec/`

**Interfaces:**
- Consumes: `PubspecDocument`, `PubspecSettings`, `CheckContext.targetBranch`, `CheckContext.base`.
- Produces: `unpinnedGitFindings(PubspecDocument, RepoPath, {required bool requireSha})`; `buildNumberRegressionFindings({required PubspecDocument snapshot, required PubspecDocument? base, required RepoPath path})`; `lockfileFindings({required PubspecDocument pubspec, required LockfileDocument lock, required RepoPath pubspecPath})`; `LockfileDocument` exposing `Map<String, LockedPackage>` with `version`, `source` (`hosted`, `git`, `path`, `sdk`) and `dependencyKind`.

- [ ] **Step 1: Write the failing tests.** Messages are asserted exactly as in `specs/rules.md`.

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

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Version and constraint parsing use `package:pub_semver`; an unparseable constraint is skipped, not an error.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add unpinned-git, build-number-regression and lockfile-out-of-sync`

### Task 3: The `assets` check

**Branch:** `feat/03-03-assets`

**Files:**
- Create: `lib/src/checks/assets/assets_check.dart`, `asset_declarations.dart`, `format_size.dart`
- Test: `test/checks/assets/asset_declarations_test.dart`, `assets_check_test.dart`, `format_size_test.dart`

**Interfaces:**
- Produces: `AssetsCheck implements Check` (`id: 'assets'`; rules `missing`, `undeclared`, `max-file-size`); `AssetDeclarations.fromPubspec(PubspecDocument, RepoPath pubspecPath)` with `bool declares(RepoPath file)` and `Iterable<DeclaredAsset> get entries`; `String formatSize(int bytes, {required int limit})`.

- [ ] **Step 1: Write the failing tests.**

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

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** A variant directory name matches a digit run, an optional `.digits`, then `x`. Sizes come from `SnapshotFiles.size`, never from reading content.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add assets check`

### Task 4: The `l10n` check

**Branch:** `feat/03-04-l10n`

**Files:**
- Create: `lib/src/checks/l10n/l10n_check.dart`, `l10n_setup.dart`, `arb_document.dart`
- Test: `test/checks/l10n/l10n_setup_test.dart`, `l10n_check_test.dart`

**Interfaces:**
- Consumes: `icuArguments`, `Documents.json`, `Documents.yaml`.
- Produces: `L10nCheck implements Check` (`id: 'l10n'`; rules `missing-key`, `placeholder-mismatch`, `unparseable`; `unused-key` is registered in plan 04, not before); `L10nSetup { RepoPath arbDir; String templateFile; RepoPath? outputDir }` from `Future<L10nSetup?> readL10nSetup(SnapshotFiles, Documents, DartPackage)`; `ArbDocument` with `Map<String, LocatedEntry> get messages` (keys not starting with `@`).

- [ ] **Step 1: Write the failing tests.**

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

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/rules.md` `l10n`.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add l10n missing-key and placeholder-mismatch`

### Task 5: Annotated-declaration facts and `codegen/stale`

**Branch:** `feat/03-05-codegen-stale`

**Files:**
- Modify: `lib/src/infrastructure/dart/syntactic_facts.dart`
- Create: `lib/src/checks/codegen/codegen_check.dart`, `codegen_signature.dart`
- Test: `test/infrastructure/dart/annotated_declarations_test.dart`, `test/checks/codegen/codegen_check_test.dart`

**Interfaces:**
- Consumes: `DartToolchain.facts`, `CodegenSettings`, `CheckContext.base`.
- Produces: `SyntacticFacts.extract` fills `annotatedDeclarations`; `CodegenCheck implements Check` (`id: 'codegen'`; rule `stale`); `CodegenSignature.of(DartFileFacts facts, List<String> suffixes)` with `List<String> generatedParts` and `AnnotatedDeclaration? firstDifference(CodegenSignature other)`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('token hash ignores whitespace and comments', () {
  expect(hashOf('@JsonSerializable()\nclass A { final int x; A(this.x); }'),
         hashOf('@JsonSerializable()\nclass A {\n  // note\n  final int x;\n  A(this.x);\n}'));
});
test('token hash changes when a field is added', () { /* ... */ });
test('annotations are names without arguments, sorted; excluded annotations do not count', () {
  expect(decl.annotations, ['JsonSerializable', 'immutableRecord']);   // @override, @Deprecated(...) alone: no entry
});
test('annotated members are named Class.member', () { /* @JsonKey on a field */ });
test('annotated class changed, generated part not in the changeset', () async {
  expect(f.single.message, '"Order" changed but order.g.dart was not updated in this change.');
});
test('same change with the generated part in the changeset passes', () async { /* ... */ });
test('only non-annotated code changed: no finding', () async { /* ... */ });
test('new source file whose generated part is absent', () async {
  expect(f.single.message, 'order.g.dart is declared as a part but is missing.');
});
test('renamed source file is compared with its previous path in the base', () async { /* ... */ });
test('generated_files_committed: false disables the check', () async { /* ... */ });
test('a file that does not parse in the snapshot is left to analyze', () async { /* facts == null: no finding */ });
test('custom generated_suffixes are honored', () async { /* .config.dart */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/rules.md` `codegen` and `specs/dart-toolchain.md` section 6. The hash is SHA-256 over token lexemes joined by one space.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add codegen/stale from annotated-declaration facts`

### Task 6: Test-call facts, `tests/solo` and `tests/new-skip`

**Branch:** `feat/03-06-tests-rules`

**Files:**
- Modify: `lib/src/infrastructure/dart/syntactic_facts.dart`
- Create: `lib/src/checks/tests/tests_check.dart`, `test_key.dart`
- Test: `test/infrastructure/dart/test_calls_test.dart`, `test/checks/tests/tests_check_test.dart`

**Interfaces:**
- Produces: `SyntacticFacts.extract` fills `testCalls`; `TestsCheck implements Check` (`id: 'tests'`; rules `solo`, `new-skip`; `affected` is registered in plan 04, not before); `String testKey(TestCall call)`; `bool isTestFile(RepoPath path, PackageMap packages)`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('calls are collected with their enclosing groups', () {
  final c = calls("group('cart', () { test('adds', () {}, skip: true); });").last;
  expect(c.groups, ['cart']); expect(c.description, 'adds'); expect(c.skip, isNotNull); expect(c.solo, isNull);
});
test('solo: false and skip: false or null are not set', () { /* ... */ });
test('a @Skip annotation on the call\'s enclosing function counts as skip', () { /* ... */ });
test('a non-literal description uses its source text', () { expect(c.description, r"'adds $n'"); });
test('only functions named in tests.functions are collected', () { /* testGoldens ignored by default */ });
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
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** New skips are found by multiset difference of skipped keys, snapshot minus base.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add tests/solo and tests/new-skip`

### Task 7: Baseline

**Branch:** `feat/03-07-baseline`

**Files:**
- Create: `lib/src/application/baseline/fingerprint.dart`, `baseline.dart`, `baseline_codec.dart`, `baseline_filter.dart`, `baseline_commands.dart`
- Create: `lib/src/cli/commands/baseline_command.dart`
- Modify: `lib/src/application/pipeline/pipeline.dart`
- Test: `test/application/baseline/*_test.dart`, `test/cli/baseline_command_test.dart`, `test/acceptance/ac23_baseline_test.dart`

**Interfaces:**
- Produces: `String normalizeSnippet(List<String> lines)`; `Future<String> fingerprintOf(Finding finding, SnapshotFiles snapshot)`; `BaselineEntry { RuleId rule; RepoPath path; String fingerprint; int count }`; `Baseline(List<BaselineEntry> entries)` with `Baseline.empty`; `Baseline decodeBaseline(String json)` throwing `ConfigException`; `String encodeBaseline(Baseline)`; `Future<BaselineOutcome> applyBaseline(List<Finding>, Baseline, SnapshotFiles)` with `kept` and `baselined`; `BaselineCommands(Pipeline, WorkingTree)` with `create({required bool force})` and `prune()` returning the message to print.

- [ ] **Step 1: Write the failing tests.**

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
test('invalid-ignore findings are never baselined', () async { /* ... */ });
test('create writes all current findings and refuses to overwrite', () async {
  expect(message, 'Wrote 3 entries to .stagelatch/baseline.json. Stage it to take effect.');
});
test('prune lowers counts and removes stale entries, and never adds', () async {
  expect(message, 'Removed 2 stale entries; 1 remain.');
});
test('the baseline is read from the snapshot, not the working tree', () async { /* ADR-0015 */ });
```

AC-23: a legacy violation is baselined and staged: commit passes. A second, new violation in the same file: commit blocked, only the new one reported. Insert lines above the old violation: still baselined. Rename the file: the old violation is reported again; `baseline prune` drops the stale entry.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** per `specs/baseline-and-suppression.md` section 4. The filter is the last link of the chain.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(baseline): add fingerprinted baseline with create and prune`

### Task 8: `--all`

**Branch:** `feat/03-08-all-flag`

**Files:**
- Modify: `lib/src/infrastructure/git/git_cli_repository.dart`, `lib/src/cli/commands/run_command.dart`, `ci_command.dart`, `lib/src/infrastructure/reporters/console_reporter.dart`
- Test: `test/infrastructure/git/resolve_all_test.dart`, `test/cli/all_flag_test.dart`

**Interfaces:**
- Produces: `GitRepository.resolve(entry, all: true)` returning a changeset that lists every regular file as `added`, with the base still resolved.

- [ ] **Step 1: Write the failing tests.**

```dart
test('all lists every regular file of the snapshot as added', () async { /* symlinks and gitlinks excluded */ });
test('the base snapshot is still available to rules', () async { expect(run.base, isNotNull); });
test('run pre-commit --all reports a violation in an unchanged file', () async { /* ... */ });
test('the header reads "all files"', () async { expect(out.toString(), startsWith('stagelatch pre-commit: all files\n')); });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** `baseline create` and `prune` switch to the public flag path.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(cli): add --all to run and ci`

### Task 9: Config JSON Schema

**Branch:** `feat/03-09-json-schema`

**Files:**
- Create: `schema/stagelatch.schema.json`
- Test: `test/application/config/schema_agreement_test.dart`

- [ ] **Step 1: Write the failing test.**

```dart
test('the schema describes every key the loader accepts, with the same type', () {
  // loader exposes its allowed-keys map; the test walks both structures
  expect(schemaKeys, loaderKeys);
});
test('the schema is valid JSON Schema draft 2020-12 with additionalProperties: false at every level', () { /* ... */ });
test('enumerations match: levels, scopes, fail_on values, hook names', () { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL, file missing.
- [ ] **Step 3: Write the schema** by hand from `specs/config.md` section 3, with a `description` per key. `rules` is an object whose property names match the rule ID pattern.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(config): publish JSON Schema for stagelatch.yaml`

### Task 10: `init` detection, documentation and 0.2.0

**Branch:** `docs/03-10-release`

**Files:**
- Modify: `lib/src/application/init/config_writer.dart`, `README.md`, `stagelatch.yaml`, `docs/plans/README.md`
- Create: `docs/rules.md` (user-facing rule reference generated from the descriptors)
- Test: `test/application/init/config_writer_test.dart`, `test/docs/rules_reference_test.dart`

- [ ] **Step 1: Write the failing tests.**

```dart
test('init lists codegen only when build_runner is a dev dependency', () { /* ... */ });
test('init lists l10n only when l10n.yaml exists, and assets only when the pubspec declares assets', () { /* ... */ });
test('init adds the yaml-language-server schema comment as the first line', () {
  expect(text, startsWith('# yaml-language-server: \$schema=https://raw.githubusercontent.com/danielcbdev/stagelatch/main/schema/stagelatch.schema.json\n'));
});
test('docs/rules.md lists every registered rule exactly once', () { /* compares with the registry */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement,** then update the README: new rules, baseline adoption guide, `--all`.
- [ ] **Step 4: Run** all four commands; `dart pub publish --dry-run` is clean.
- [ ] **Step 5: Commit.** `docs: document 0.2.0 rules and baseline adoption`
- [ ] **Step 6: Release** `0.2.0` per workflow section 8.

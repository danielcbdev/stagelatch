# Foundation (0.1.0-dev.1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `0.1.0-dev.1`: `init`, `install`, `uninstall` and `run pre-commit` with two `pubspec` rules, judged on the index, with no Dart analysis.

**Architecture:** Five modules with ports and adapters (ADR-0012). This plan builds the domain values, the git adapter over `ls-files` and one persistent `cat-file --batch`, the config loader, the pipeline and the hook installer, wired in one composition root.

**Tech Stack:** Dart `^3.13.0`; `args`, `collection`, `glob`, `meta`, `path`, `pub_semver`, `source_span`, `yaml`; `test`, `very_good_analysis`, `coverage`; git 2.30+.

**Spec:** [`architecture.md`](../architecture.md); [`specs/cli.md`](../specs/cli.md) 1–4; [`specs/config.md`](../specs/config.md); [`specs/git.md`](../specs/git.md) 1–5, 7–9; [`specs/rules.md`](../specs/rules.md) `pubspec`; [`engineering/`](../engineering/).

## Global Constraints

- Dart SDK constraint `^3.13.0`. Runtime dependencies only from the allowlist in `coding-standards.md` section 2.
- Imports obey the module table of `architecture.md` section 2; `test/architecture/layering_test.dart` passes.
- `dart format --output=none --set-exit-if-changed .`, `dart analyze --fatal-infos` and `dart test` pass on Ubuntu, macOS and Windows, Dart stable and beta.
- Line coverage of `lib/src/domain`, `lib/src/checks`, `lib/src/application` is at least 90%.
- Every public member has a `///` doc comment; every file under `lib/src` has a library doc comment.
- Every user-facing string matches the spec character for character. Console output is ASCII.
- Security rules S1–S13 hold. Git is spawned with argument lists; the only mutating git commands are those of S4.
- No network, no prompts, no `print`, no `dart:io` outside `infrastructure` and `cli`.
- One pull request per task into `develop`, squash-merged, Conventional Commits title.

## Review Focus

- **A path containing a newline or non-UTF-8 bytes.** Expected: handled through `-z` and blob ids, or a clear usage error; never a crash or a mis-split path. Pinned in Task 6.
- **`git commit -a` and `git commit <path>`,** where git uses a temporary index. Expected: the tool reads that index because it inherits `GIT_INDEX_FILE`. Pinned in Task 14 (AC-15).
- **A hook script written with CRLF on Windows.** Expected: always LF, or `sh` fails with `\r: command not found`. Pinned in Task 12.
- **`pubspec.yaml` that is valid YAML but not a map,** or has `dependencies: null`. Expected: `pubspec/unparseable` or no finding; never an exception. Pinned in Task 9.
- **A file name containing terminal escape sequences.** Expected: printed with the control characters removed. Pinned in Task 11.

---

### Task 1: Scaffold and guard rails

**Branch:** `build/01-01-scaffold`

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, `.gitattributes`, `LICENSE`, `README.md`, `CHANGELOG.md`, `SECURITY.md`
- Create: `bin/stagelatch.dart`, `lib/stagelatch.dart`, `lib/src/version.dart`
- Create: `test/architecture/layering_test.dart`, `test/version_test.dart`, `tool/check_coverage.dart`
- Create: `.github/workflows/ci.yaml`, `.github/pull_request_template.md`

**Interfaces:**
- Produces: `const String packageVersion` in `lib/src/version.dart`; `List<String> forbiddenImports({required String module, required Iterable<String> imports})` in the layering test's helper; `dart run tool/check_coverage.dart` exiting non-zero below the floor.

- [x] **Step 1: Write the failing tests.**

```dart
test('domain may not import dart:io or another module', () {
  expect(
    forbiddenImports(module: 'domain', imports: ['dart:io', 'package:stagelatch/src/application/errors.dart', 'package:meta/meta.dart']),
    ['dart:io', 'package:stagelatch/src/application/errors.dart'],
  );
});
test('checks may import domain and pub_semver only', () {
  expect(forbiddenImports(module: 'checks', imports: ['package:stagelatch/src/domain/finding.dart', 'package:pub_semver/pub_semver.dart', 'package:yaml/yaml.dart']), ['package:yaml/yaml.dart']);
});
test('every file under lib/src obeys the module table', () { /* walks lib/src, asserts no violations */ });
test('packageVersion equals the version in pubspec.yaml', () { /* reads pubspec.yaml */ });
```

- [x] **Step 2: Run** `dart test test/architecture test/version_test.dart`. Expected: FAIL, `forbiddenImports` and `packageVersion` undefined.
- [x] **Step 3: Implement.**
  - `pubspec.yaml`: `name: stagelatch`, `version: 0.1.0-dev.1`, `environment: sdk: ^3.13.0`, `executables: {stagelatch: stagelatch}`, `repository: https://github.com/danielcbdev/stagelatch`, dependencies with the constraints of `coding-standards.md` section 2.
  - `analysis_options.yaml`: exactly as in `coding-standards.md` section 1.
  - `.gitattributes`: `* text=auto eol=lf`, so Windows checkouts keep LF and golden files match.
  - `lib/src/version.dart`: the constant, with the comment `// x-release-please-version` on the same line.
  - `bin/stagelatch.dart`: `main` prints `stagelatch <version>` for now; replaced in Task 13.
  - The module table is encoded once, as data, in the layering test. Relative imports are resolved to module names before checking.
  - `tool/check_coverage.dart`: reads `coverage/lcov.info`, computes line coverage for the three directories together, exits 1 below 90%, and exits 0 with `No covered files yet.` when none of the three has a file.
  - `ci.yaml`: `on: [push to develop and main, pull_request]`; `permissions: contents: read`; matrix `os: [ubuntu-latest, macos-latest, windows-latest]` by `sdk: [stable, beta]`; steps: checkout with `fetch-depth: 0`, `dart-lang/setup-dart` pinned by SHA, `dart pub get`, format check, `dart analyze --fatal-infos`, `dart test --coverage-path=coverage/lcov.info`, and on `ubuntu-latest`/`stable` only, `dart run tool/check_coverage.dart`. The format check runs on `stable` only.
  - `SECURITY.md`: report through GitHub private vulnerability reporting.
- [x] **Step 4: Run** the four commands of `testing.md` section 7. Expected: PASS.
- [x] **Step 5: Commit.** `build: scaffold package, lints, layering test and CI`

### Task 2: Domain values

**Branch:** `feat/01-02-domain-values`

**Files:**
- Create: `lib/src/domain/repo_path.dart`, `rule_id.dart`, `severity.dart`, `location.dart`, `finding.dart`, `fix.dart`
- Test: `test/domain/repo_path_test.dart`, `rule_id_test.dart`, `location_test.dart`, `finding_test.dart`

**Interfaces:**
- Produces: `RepoPath`, `RuleId`, `RuleDescriptor`, `Severity`, `RuleLevel`, `Position`, `Location`, `Finding`, `Fix` exactly as in `architecture.md` section 4; plus `static int Finding.compare(Finding a, Finding b)` ordering by path, line, column, rule, message.

- [x] **Step 1: Write the failing tests.**

```dart
test('RepoPath rejects paths that are not clean repository paths', () {
  for (final bad in ['', '/a', 'a/', 'a//b', './a', 'a/../b', 'a/./b', 'a\u0000b']) {
    expect(() => RepoPath(bad), throwsFormatException, reason: bad);
  }
});
test('RepoPath keeps backslashes and spaces as ordinary characters', () {
  expect(RepoPath(r'lib/a b\c.dart').basename, r'a b\c.dart');
});
test('RepoPath exposes basename, extension, parent and containment', () {
  final p = RepoPath('lib/src/a.g.dart');
  expect(p.basename, 'a.g.dart'); expect(p.extension, '.dart');
  expect(p.parent, RepoPath('lib/src')); expect(RepoPath('a.dart').parent, isNull);
  expect(p.isWithin(RepoPath('lib')), isTrue); expect(p.isWithin(RepoPath('li')), isFalse);
});
test('RuleId.parse accepts check/rule and rejects everything else', () {
  expect(RuleId.parse('pubspec/path-dependency'), const RuleId('pubspec', 'path-dependency'));
  for (final bad in ['pubspec', '/x', 'a/', 'a/b/c', 'A/b', 'a b/c']) {
    expect(() => RuleId.parse(bad), throwsFormatException, reason: bad);
  }
  expect(RuleId.parse('analyze/unused_import').rule, 'unused_import');
});
test('Finding.compare orders by path, line, column, rule, message', () { /* five findings, shuffled, sorted, exact order */ });
test('value types implement == and hashCode', () { /* each type: equal pair, unequal pair */ });
```

- [x] **Step 2: Run** `dart test test/domain`. Expected: FAIL, types undefined.
- [x] **Step 3: Implement** the types. `RepoPath` compares by code unit so ordering is identical on every platform. `RuleId` parts match `[a-z0-9][a-z0-9_-]*`. `Position` asserts both values are at least 1.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(domain): add path, rule, location, finding and fix values`

### Task 3: Domain contracts and their fakes

**Branch:** `feat/01-03-domain-contracts`

**Files:**
- Create: `lib/src/domain/change_set.dart`, `snapshot.dart`, `documents.dart`, `package_map.dart`, `check.dart`, `dart/dart_toolchain.dart`, `dart/dart_file_facts.dart`
- Create: `test/support/fake_snapshot_files.dart`, `fake_documents.dart`, `fake_check_context.dart`, `located.dart`
- Test: `test/domain/change_set_test.dart`, `test/support/fakes_test.dart`

**Interfaces:**
- Produces: every type of `architecture.md` sections 4, 4.1 and 4.2, and the fact types of `specs/dart-toolchain.md` section 6. `PackageMap` and `DartPackage` are declared here with `DartPackage? packageOf(RepoPath path)` and `List<DartPackage> get packages`; the builder comes in plan 02.
- Produces (test support): `FakeSnapshotFiles(Map<String, Object> files)` where a `String` value is text and a `List<int>` value is bytes; `FakeDocuments()` that parses with the real adapter once Task 7 lands, and until then from `Map<String, LocatedNode>`; `FakeCheckContext({changes, snapshot, base, enabled, settings})`; `located.dart` helpers `map({...})`, `list([...])`, `scalar(value)` that build `LocatedNode`s with given positions.

- [x] **Step 1: Write the failing tests.**

```dart
test('ChangeSet sorts by path and exposes present and lookup', () {
  final set = ChangeSet([
    FileChange(path: RepoPath('b.dart'), kind: ChangeKind.deleted),
    FileChange(path: RepoPath('a.dart'), kind: ChangeKind.modified),
    FileChange(path: RepoPath('c.dart'), kind: ChangeKind.renamed, previousPath: RepoPath('old.dart')),
  ]);
  expect(set.changes.map((c) => c.path.value), ['a.dart', 'b.dart', 'c.dart']);
  expect(set.present.map((c) => c.path.value), ['a.dart', 'c.dart']);
  expect(set[RepoPath('c.dart')]!.previousPath, RepoPath('old.dart'));
  expect(set[RepoPath('zzz')], isNull);
});
test('FakeSnapshotFiles.readText returns null for bytes containing NUL', () async {
  final files = FakeSnapshotFiles({'a.bin': [0, 1, 2], 'a.txt': 'hi'});
  expect(await files.readText(RepoPath('a.bin')), isNull);
  expect(await files.readText(RepoPath('a.txt')), 'hi');
  expect(await files.readText(RepoPath('missing')), isNull);
});
```

- [x] **Step 2: Run** `dart test test/domain test/support`. Expected: FAIL, types undefined.
- [x] **Step 3: Implement** the interfaces and values. Interfaces carry full doc comments stating each contract (null meanings, ordering). `renamed` requires `previousPath`; every other kind forbids it (assert in the constructor).
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(domain): add change set, snapshot, document and check contracts`

### Task 4: Errors, exit codes and environment

**Branch:** `feat/01-04-errors-environment`

**Files:**
- Create: `lib/src/application/errors.dart`, `lib/src/application/environment.dart`, `lib/src/cli/exit_codes.dart`
- Test: `test/application/environment_test.dart`, `test/cli/exit_codes_test.dart`

**Interfaces:**
- Produces: `UsageException(String message)`, `ConfigException(String message, {Location? location})`, `InternalException(String message, {String? where, Object? cause, StackTrace? stackTrace})`; `enum ExitCode { pass(0), findings(1), usage(64), internal(70), config(78) }` with `int get code` and `static ExitCode forException(StagelatchException e)`; `Environment({required String workingDirectory, required Map<String, String> variables, required bool stdoutIsTerminal, required bool stdinIsTerminal, bool? colorOverride})` with `bool get useColor`.

- [x] **Step 1: Write the failing tests.**

```dart
test('useColor follows override, then terminal and NO_COLOR', () {
  Environment env({bool tty = true, Map<String, String> vars = const {}, bool? override}) =>
      Environment(workingDirectory: '/r', variables: vars, stdoutIsTerminal: tty, stdinIsTerminal: tty, colorOverride: override);
  expect(env().useColor, isTrue);
  expect(env(tty: false).useColor, isFalse);
  expect(env(vars: {'NO_COLOR': '1'}).useColor, isFalse);
  expect(env(vars: {'NO_COLOR': ''}).useColor, isTrue);   // empty value does not count
  expect(env(tty: false, override: true).useColor, isTrue);
  expect(env(override: false).useColor, isFalse);
});
test('exit codes map one to one', () {
  expect(ExitCode.forException(UsageException('x')).code, 64);
  expect(ExitCode.forException(ConfigException('x')).code, 78);
  expect(ExitCode.forException(InternalException('x')).code, 70);
});
```

- [x] **Step 2: Run.** Expected: FAIL, types undefined.
- [x] **Step 3: Implement.** `ConfigException.toString()` renders `stagelatch.yaml:<line>:<column>: <message>` when a location is present.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(cli): add error hierarchy, exit codes and environment value`

### Task 5: Git process, persistent blob reader and the test repository

**Branch:** `feat/01-05-cat-file-batch`

**Files:**
- Create: `lib/src/infrastructure/git/git_process.dart`, `cat_file_batch.dart`
- Create: `test/support/temp_repo.dart`
- Test: `test/infrastructure/git/git_process_test.dart`, `cat_file_batch_test.dart`

**Interfaces:**
- Consumes: `InternalException`, `Environment`.
- Produces: `GitProcess({required String workingDirectory, required Map<String, String> environment})` with `Future<GitResult> run(List<String> args, {List<int>? stdin, Set<int> okExitCodes = const {0}})` and `Future<Process> start(List<String> args)`; `GitResult { int exitCode; Uint8List stdout; String stderr; String get text; List<String> get nulSeparated }`; `CatFileBatch(GitProcess git)` with `Future<Uint8List> read(String blobId)`, `Future<int> size(String blobId)`, `Future<void> close()`, `int get spawnCount`; `TempRepo` as in `testing.md` section 3 (its `stagelatch` method is added in Task 13).

- [x] **Step 1: Write the failing tests.**

```dart
test('reads a blob byte for byte, including NUL and CRLF', () async {
  final repo = await TempRepo.create();
  await repo.writeBytes('a.bin', [0x41, 0x00, 0x0d, 0x0a, 0x42]);
  await repo.stage('a.bin');
  final id = (await repo.git(['rev-parse', ':a.bin'])).trim();
  expect(await batch.read(id), [0x41, 0x00, 0x0d, 0x0a, 0x42]);
});
test('one process serves many reads', () async {
  for (var i = 0; i < 100; i++) { await batch.read(id); }
  expect(batch.spawnCount, 1);
});
test('an unknown id is an internal error', () async {
  expect(() => batch.read('0' * 40), throwsA(isA<InternalException>()));
});
test('size comes without content', () async { expect(await batch.size(id), 5); });
test('close ends the process; a later read fails', () async { /* ... */ });
test('run returns stdout split on NUL', () async { /* git ls-files -z */ });
test('an unexpected exit code raises InternalException naming the command and stderr', () async { /* git rev-parse --verify nope */ });
```

- [x] **Step 2: Run** `dart test test/infrastructure/git`. Expected: FAIL, types undefined.
- [x] **Step 3: Implement** per `specs/git.md` sections 1 and 3.1. Requests are chained on a single future so only one is on the pipe at a time. `--batch` and `--batch-check` are two lazily started processes. Every flag passed to git has a comment. `TempRepo.create` applies the local git config listed in `testing.md` section 3; `stageContent` uses `hash-object -w --stdin` and `update-index --add --cacheinfo`.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(git): add git process wrapper and persistent cat-file reader`

### Task 6: Snapshots, layout and the pre-commit changeset

**Branch:** `feat/01-06-git-repository`

**Files:**
- Create: `lib/src/application/entry_point.dart`, `lib/src/application/ports/git_repository.dart`
- Create: `lib/src/infrastructure/git/git_snapshot_files.dart`, `git_cli_repository.dart`, `name_status_parser.dart`
- Create: `test/support/fake_git_repository.dart`
- Test: `test/infrastructure/git/git_snapshot_files_test.dart`, `git_cli_repository_test.dart`, `name_status_parser_test.dart`

**Interfaces:**
- Consumes: `GitProcess`, `CatFileBatch`, domain contracts.
- Produces: `EntryPoint` and subtypes, `PushedRef`; `GitRepository`, `SnapshotRef`, `IndexSnapshot`, `CommitSnapshot`, `ResolvedRun`, `RepoLayout { root, gitDir, commonDir, hooksDir, branch, mergeInProgress, rebaseInProgress, shallow }`, `AppliedFix { rule, path, worktreeUpdated }`; `GitCliRepository implements GitRepository` supporting `layout`, `files`, `divergingFromWorktree`, `close`, and `resolve` for `PreCommitEntry` only (`PrePushEntry` and `CiEntry` throw `UnsupportedError` until plan 02; `applyFixes` likewise); `List<FileChange> parseNameStatus(List<String> nulFields)`.

- [x] **Step 1: Write the failing tests.**

```dart
test('parseNameStatus maps status letters and reads both paths of a rename', () {
  expect(parseNameStatus(['A', 'a.dart', 'M', 'b.dart', 'D', 'c.dart', 'R087', 'old.dart', 'new.dart', 'T', 'd']), [
    FileChange(path: RepoPath('a.dart'), kind: ChangeKind.added),
    FileChange(path: RepoPath('b.dart'), kind: ChangeKind.modified),
    FileChange(path: RepoPath('c.dart'), kind: ChangeKind.deleted),
    FileChange(path: RepoPath('new.dart'), kind: ChangeKind.renamed, previousPath: RepoPath('old.dart')),
    FileChange(path: RepoPath('d'), kind: ChangeKind.typeChanged),
  ]);
});
test('index snapshot returns staged content, not working tree content', () async {
  await repo.write('a.txt', 'disk'); await repo.stageContent('a.txt', 'staged');
  expect(await repo2.files(IndexSnapshot()).readText(RepoPath('a.txt')), 'staged');
});
test('readText is null for binary, symlink, gitlink, invalid UTF-8 and files over 5 MiB', () async { /* one case each */ });
test('a UTF-8 byte order mark is stripped; CRLF is preserved', () async { /* ... */ });
test('unmerged index entries are a usage error', () async {
  expect(() => files.list(), throwsA(isA<UsageException>().having((e) => e.message, 'message', 'The index has unmerged paths; resolve conflicts first.')));
});
test('pre-commit changeset on an unborn branch lists everything as added and has no base', () async { /* ... */ });
test('pre-commit changeset during a merge keeps only paths that differ from both parents', () async {
  // main changes a.txt, feature changes b.txt, merge conflicts on c.txt and is resolved by hand
  expect(run.changes.changes.map((c) => c.path.value), ['c.txt']);
});
test('paths with space, quote, non-ASCII and newline survive', () async {
  for (final name in ['a b.txt', 'q"uote.txt', 'ação.txt', 'new\nline.txt']) { /* stage, expect in changeset and readable */ }
}, testOn: '!windows');
test('layout reports the hooks directory under core.hooksPath and in a linked worktree', () async { /* ... */ });
test('divergingFromWorktree lists unstaged edits and deletions, sorted', () async { /* ... */ });
```

- [x] **Step 2: Run** `dart test test/infrastructure/git`. Expected: FAIL, types undefined.
- [x] **Step 3: Implement** per `specs/git.md` sections 2, 3, 4.1 and 5. The snapshot listing is parsed once and cached. `FakeGitRepository` in `test/support` holds snapshots as `FakeSnapshotFiles` and records `applyFixes` calls. On Windows the newline-in-path case is skipped with the reason "NTFS forbids the character".
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(git): add index snapshots, layout and pre-commit changeset`

### Task 7: YAML and JSON documents with locations

**Branch:** `feat/01-07-documents`

**Files:**
- Create: `lib/src/infrastructure/documents/structured_documents.dart`
- Modify: `test/support/fake_documents.dart` (delegate to the real parser)
- Test: `test/infrastructure/documents/structured_documents_test.dart`

**Interfaces:**
- Consumes: `Documents`, `DocumentResult`, `LocatedNode` and subtypes, `SnapshotFiles`.
- Produces: `StructuredDocuments implements Documents`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('yaml returns 1-based locations for keys and values', () async {
  final files = FakeSnapshotFiles({'p.yaml': 'name: app\ndependencies:\n  foo:\n    path: ../foo\n'});
  final root = (await docs.yaml(files, RepoPath('p.yaml')) as DocumentParsed).root as LocatedMap;
  final deps = root.entries['dependencies']!;
  expect(deps.keyLocation.start, const Position(2, 1));
  final path = ((deps.value as LocatedMap).entries['foo']!.value as LocatedMap).entries['path']!;
  expect(path.value.location.start, const Position(4, 11));
  expect((path.value as LocatedScalar).value, '../foo');
});
test('missing file is DocumentMissing; unreadable text is DocumentInvalid at 1:1', () async { /* ... */ });
test('invalid YAML is DocumentInvalid with the parser position', () async {
  final r = await docs.yaml(FakeSnapshotFiles({'p.yaml': 'a: [1, 2'}), RepoPath('p.yaml')) as DocumentInvalid;
  expect(r.location.start.line, 1);
});
test('duplicate keys are invalid', () async { /* 'a: 1\na: 2\n' */ });
test('non-string map keys are invalid', () async { /* '1: a\n' */ });
test('json rejects YAML that is not JSON', () async {
  expect(await docs.json(FakeSnapshotFiles({'a.json': 'a: 1'}), RepoPath('a.json')), isA<DocumentInvalid>());
});
test('json returns located nodes for valid JSON', () async { /* {"type": "service_account"} */ });
```

- [ ] **Step 2: Run.** Expected: FAIL, `StructuredDocuments` undefined.
- [ ] **Step 3: Implement.** YAML: `loadYamlNode` and a recursive conversion from `YamlNode` spans to `LocatedNode`. JSON: validate with `jsonDecode` first, then obtain locations by parsing the same text as YAML, since JSON is a subset. Anchors and aliases are resolved by the YAML library; a document that still exceeds 100,000 nodes after conversion is `DocumentInvalid` ("document is too large").
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(documents): parse YAML and JSON into located nodes`

### Task 8: Config model and loader

**Branch:** `feat/01-08-config`

**Files:**
- Create: `lib/src/application/config/config.dart`, `settings.dart`, `hook_selector.dart`, `value_parsers.dart`, `config_loader.dart`, `check_catalog.dart`
- Create: `lib/src/application/ports/working_tree.dart`, `test/support/fake_working_tree.dart`
- Test: `test/application/config/value_parsers_test.dart`, `config_loader_test.dart`

**Interfaces:**
- Consumes: `Documents`, `SnapshotFiles`, `ConfigException`, `RuleId`, `RuleLevel`.
- Produces:
  - `int parseSize(String)`, `Duration parseDuration(String)`, both throwing `FormatException`.
  - `HookSelector { String check; String? rule }` with `HookSelector.parse`.
  - `Config { Version? minVersion; Map<String, List<HookSelector>> hooks; Map<RuleId, RuleLevel> rules; List<Glob> exclude; String? sdkPath; Duration timeBudget; String baselinePath; T settings<T extends Object>() }` and the settings classes of `specs/config.md` section 8, each with the defaults of section 3.
  - `CheckCatalog { Set<String> get checkIds; bool hasRule(RuleId id); bool hasDynamicRules(String check); List<String> get preCommitDefault; List<String> get prePushDefault }`.
  - `WorkingTree { Future<String?> readText(RepoPath path); Future<void> writeText(RepoPath path, String content); Future<bool> exists(RepoPath path) }`.
  - `ConfigLoader(Documents documents, WorkingTree worktree)` with `Future<LoadedConfig> load(SnapshotFiles snapshot, {required Version toolVersion, required CheckCatalog catalog})`; `LoadedConfig { Config config; List<String> notices }`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('parseSize uses binary units', () {
  expect(parseSize('500KB'), 512000); expect(parseSize('1MB'), 1048576); expect(parseSize('10B'), 10);
  for (final bad in ['', '5', 'KB', '-1KB', '1.5MB', '1 KB', '1kb']) { expect(() => parseSize(bad), throwsFormatException, reason: bad); }
});
test('parseDuration accepts ms and decimal seconds', () {
  expect(parseDuration('2s'), const Duration(seconds: 2)); expect(parseDuration('1.5s'), const Duration(milliseconds: 1500));
  expect(parseDuration('250ms'), const Duration(milliseconds: 250));
  for (final bad in ['0s', '2', 's', '1.5ms', '-1s']) { expect(() => parseDuration(bad), throwsFormatException, reason: bad); }
});
test('no config anywhere yields the documented defaults', () async {
  final c = (await loader.load(FakeSnapshotFiles({}), toolVersion: v, catalog: catalog)).config;
  expect(c.timeBudget, const Duration(seconds: 2)); expect(c.baselinePath, '.stagelatch/baseline.json');
  expect(c.settings<FormatSettings>().fix, isTrue);
  expect(c.settings<AssetsSettings>().maxFileSize, 512000);
  expect(c.settings<AnalyzeSettings>().failOn, {DiagnosticSeverity.error, DiagnosticSeverity.warning});
});
test('the full example of the spec loads', () async { /* text copied from specs/config.md section 2 */ });
test('config in the snapshot wins over the working tree', () async { /* ADR-0015 */ });
test('config only in the working tree is used with a notice', () async {
  expect(loaded.notices, ['stagelatch.yaml is not staged; using the working tree copy.']);
});
test('bare off parses as the off level; true is rejected', () async { /* rules: {pubspec/path-dependency: off} */ });
// One test per row of specs/config.md section 5, asserting message and location, for example:
test('unknown key reports its position and parent', () async {
  final e = await loadError('pubspec:\n  forbid: []\n');
  expect(e.toString(), 'stagelatch.yaml:2:3: Unknown key "forbid" under "pubspec".');
});
test('older tool than min_version is a config error with the upgrade hint', () async {
  expect((await loadError('min_version: 9.0.0\n')).message,
      'This repository requires stagelatch >= 9.0.0; you have 0.1.0-dev.1. Run: dart pub global activate stagelatch');
});
test('custom_checks is reserved', () async {
  expect((await loadError('custom_checks: {}\n')).message, 'custom_checks requires stagelatch >= 1.0.0.');
});
```

- [ ] **Step 2: Run** `dart test test/application/config`. Expected: FAIL, types undefined.
- [ ] **Step 3: Implement.** The loader walks the `LocatedNode` tree with one small function per key; each function either returns a typed value or throws `ConfigException` with the node's location. The set of allowed keys per section is a constant map, used both for validation and for the "unknown key" message. Validation stops at the first problem in document order.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(config): add typed config model and strict loader`

### Task 9: The `pubspec` check, first three rules

**Branch:** `feat/01-09-pubspec-check`

**Files:**
- Create: `lib/src/checks/pubspec/pubspec_check.dart`, `path_dependency.dart`, `dependency_overrides.dart`, `pubspec_document.dart`
- Test: `test/checks/pubspec/path_dependency_test.dart`, `dependency_overrides_test.dart`, `pubspec_check_test.dart`

**Interfaces:**
- Consumes: `Check`, `CheckContext`, `Documents`, `LocatedNode`, `PubspecSettings`.
- Produces: `PubspecCheck implements Check` with `id == 'pubspec'`, `phase == CheckPhase.verify`, and descriptors for `pubspec/path-dependency`, `pubspec/dependency-overrides`, `pubspec/unparseable`; `PubspecDocument` wrapping a `LocatedMap` with `Iterable<DependencyEntry> dependencies({required bool includeDev})` and `LocatedEntry? get overrides`; rule functions `List<Finding> pathDependencyFindings(PubspecDocument doc, RepoPath pubspecPath, Set<RepoPath> pubspecsInSnapshot)` and `List<Finding> dependencyOverridesFindings(PubspecDocument doc, RepoPath pubspecPath)`.

- [ ] **Step 1: Write the failing tests.** Each asserts the complete `Finding`.

```dart
test('path leaving the repository is reported at the path value', () async {
  final findings = await run({'pubspec.yaml': 'name: app\ndependencies:\n  design_system:\n    path: ../design_system\n'});
  expect(findings, [
    Finding(rule: RuleId.parse('pubspec/path-dependency'), severity: Severity.error,
      message: 'Dependency "design_system" uses a path that is not a package in this repository: ../design_system.',
      location: Location(RepoPath('pubspec.yaml'), const Position(4, 11), const Position(4, 27))),
  ]);
});
test('path to a package present in the snapshot is allowed', () async {
  expect(await run({'app/pubspec.yaml': 'name: app\ndependencies:\n  ui:\n    path: ../packages/ui\n', 'packages/ui/pubspec.yaml': 'name: ui\n'}, changed: ['app/pubspec.yaml']), isEmpty);
});
test('path inside the repository without a pubspec is reported', () async { /* packages/ui has no pubspec.yaml */ });
test('dev_dependencies are checked; dependency_overrides are not, by this rule', () async { /* ... */ });
test('non-empty dependency_overrides is reported at the key with sorted names', () async {
  expect(findings.single.message, 'dependency_overrides must not be committed: http, intl.');
  expect(findings.single.location.start, const Position(3, 1));
});
test('empty or null dependency_overrides is not reported', () async { /* 'dependency_overrides:\n' and '{}' */ });
test('a changed pubspec_overrides.yaml is reported at 1:1', () async {
  expect(findings.single.message, 'pubspec_overrides.yaml must not be committed.');
});
test('invalid YAML yields pubspec/unparseable and no other finding', () async {
  expect(findings.single.rule, RuleId.parse('pubspec/unparseable'));
  expect(findings.single.message, startsWith('pubspec.yaml is not valid YAML: '));
});
test('a pubspec whose root is a list is unparseable; dependencies: null is fine', () async { /* ... */ });
test('a deleted pubspec and an unchanged pubspec are not inspected', () async { /* ... */ });
test('a disabled rule produces nothing', () async { /* enabled: {pubspec/dependency-overrides} only */ });
```

- [ ] **Step 2: Run** `dart test test/checks/pubspec`. Expected: FAIL, `PubspecCheck` undefined.
- [ ] **Step 3: Implement.** Path resolution is pure string work on `RepoPath` segments: join the pubspec's directory with the dependency path, normalize `.` and `..`, and treat an escape above the root, an absolute path, or a Windows drive path as "leaves the repository". The check asks the snapshot for the list of `pubspec.yaml` paths once per run.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(checks): add pubspec path-dependency, dependency-overrides and unparseable rules`

### Task 10: Pipeline, registry and finding filters

**Branch:** `feat/01-10-pipeline`

**Files:**
- Create: `lib/src/application/pipeline/pipeline.dart`, `check_registry.dart`, `selection.dart`, `finding_filters.dart`, `run_report.dart`, `pipeline_check_context.dart`
- Create: `lib/src/application/ports/clock.dart`, `reporter.dart`; `test/support/fake_clock.dart`, `fake_check.dart`
- Test: `test/application/pipeline/selection_test.dart`, `finding_filters_test.dart`, `pipeline_test.dart`

**Interfaces:**
- Consumes: `GitRepository`, `ConfigLoader`, `Check`, `Config`, `Documents`, `WorkingTree`.
- Produces: `CheckRegistry(List<Check> checks) implements CheckCatalog` with `List<Check> get checks`; `Set<RuleId> enabledRules(List<HookSelector> selectors, CheckRegistry registry)`; `RunRequest({required EntryPoint entry, bool all = false, bool allowFixes = true})`; `RunReport`, `CheckTiming { id, duration, errors, warnings, fixed }`, `Verdict`; `Clock`; `Reporter`; `Pipeline({required GitRepository git, required ConfigLoader configLoader, required CheckRegistry registry, required Documents documents, required Clock clock, required Version toolVersion})` with `Future<List<RunReport>> run(RunRequest request)`; filter functions `applyLevels`, `applyExclude`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('a check selector enables all its rules; a rule selector enables one', () {
  expect(enabledRules([HookSelector.parse('pubspec'), HookSelector.parse('tests/solo')], registry),
      {RuleId.parse('pubspec/path-dependency'), RuleId.parse('pubspec/dependency-overrides'), RuleId.parse('pubspec/unparseable'), RuleId.parse('tests/solo')});
});
test('level off drops, warning downgrades, error upgrades', () { /* three findings */ });
test('exclude drops findings by glob on the repository path', () { /* lib/generated/** */ });
test('findings are sorted regardless of check completion order', () async {
  // two FakeChecks completing in reverse order
  expect(report.findings.map((f) => f.location.path.value), ['a.yaml', 'b.yaml']);
});
test('registry order does not change the report', () async { /* run twice with reversed registry, compare findings */ });
test('warnings alone pass; one error fails', () async { /* Verdict.pass, Verdict.fail */ });
test('a check that throws becomes InternalException naming the check', () async {
  expect(() => pipeline.run(request), throwsA(isA<InternalException>().having((e) => e.where, 'where', 'check "boom"')));
});
test('exceeding the time budget sets the flag and changes nothing else', () async {
  // FakeClock advances 3s inside the check; time_budget is 2s
  expect(report.budgetExceeded, isTrue); expect(report.findings, sameFindingsAsWithinBudget);
});
test('fix phase applies fixes to an index snapshot and verify sees the new content', () async {
  // FakeCheck(phase: fix) returns one Fix; a verify FakeCheck records the text it reads
  expect(git.appliedFixes.single.path, RepoPath('a.dart')); expect(verifySaw, 'fixed');
  expect(report.fixes.single.worktreeUpdated, isTrue); expect(report.findings, isEmpty);
});
test('allowFixes false keeps fix-phase findings and applies nothing', () async { /* ... */ });
test('a check with no enabled rule does not run', () async { /* FakeCheck.runCount == 0 */ });
test('config notices are carried into the report', () async { /* ... */ });
```

- [ ] **Step 2: Run** `dart test test/application/pipeline`. Expected: FAIL, `Pipeline` undefined.
- [ ] **Step 3: Implement** the eight steps of `architecture.md` section 5.3. The filter chain is a list of pure functions applied in the order of `specs/baseline-and-suppression.md` section 1; inline ignore and baseline are added in later plans at their positions. `PipelineCheckContext` creates `context.dart` lazily and throws `UnsupportedError('Dart toolchain arrives in 0.1.0')` until plan 02 wires it.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(pipeline): add two-phase pipeline, selection and finding filters`

### Task 11: Console reporter and output sanitizer

**Branch:** `feat/01-11-console-reporter`

**Files:**
- Create: `lib/src/application/text/sanitize.dart`, `lib/src/infrastructure/reporters/console_reporter.dart`, `ansi.dart`
- Create: `test/goldens/console/*.txt`
- Test: `test/application/text/sanitize_test.dart`, `test/infrastructure/reporters/console_reporter_test.dart`

**Interfaces:**
- Consumes: `RunReport`, `Reporter`.
- Produces: `String sanitizeForTerminal(String text)`; `ConsoleReporter(StringSink out, {required bool color}) implements Reporter`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('control characters are removed, printable text is kept', () {
  expect(sanitizeForTerminal('a\u001b[31mb\u0007c\u009bd'), 'a[31mbcd');
  expect(sanitizeForTerminal('ação.dart'), 'ação.dart');
  expect(sanitizeForTerminal('line\nbreak\ttab'), 'line break tab');
});
test('matches the golden for a blocked commit', () { /* goldens/console/blocked.txt: the example of specs/cli.md section 4 */ });
test('matches the golden for a clean run', () { /* "0 errors, 0 warnings. Commit allowed. (0.1s)" */ });
test('matches the golden with notices, a budget note and suppressed counts', () { /* ... */ });
test('singular and plural forms', () { /* 1 file / 2 files; 1 error / 2 errors; 1 warning */ });
test('durations render as ms below one second and as seconds above', () { /* 999ms, 1.0s, 12.3s */ });
test('color adds escape sequences and removing them yields the plain golden', () { /* ... */ });
test('a path with escape sequences is printed sanitized', () { /* ... */ });
```

- [ ] **Step 2: Run.** Expected: FAIL, `ConsoleReporter` undefined.
- [ ] **Step 3: Implement** the layout of `specs/cli.md` section 4. Column widths are computed from the rows. Every repository-derived string goes through `sanitizeForTerminal`. Golden files end with one newline and use LF.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(reporters): add console reporter and terminal sanitizer`

### Task 12: Hook script and installer

**Branch:** `feat/01-12-hook-installer`

**Files:**
- Create: `lib/src/application/hooks/hook_name.dart`, `hook_script.dart`, `hook_installer.dart`, `lib/src/application/ports/hook_store.dart`
- Create: `lib/src/infrastructure/io/file_hook_store.dart`, `test/support/fake_hook_store.dart`
- Test: `test/application/hooks/hook_script_test.dart`, `hook_installer_test.dart`, `test/infrastructure/io/file_hook_store_test.dart`

**Interfaces:**
- Consumes: `RepoLayout`.
- Produces: `enum HookName { preCommit('pre-commit'), prePush('pre-push') }`; `String renderHookScript(HookName hook)`; `bool isManagedHook(String content)`; `HookStore { String pathOf(HookName); Future<String?> read(HookName); Future<void> write(HookName, String content); Future<void> delete(HookName); Future<String> backup(HookName); Future<String?> restoreLatestBackup(HookName); Future<bool> get directoryIsTracked }`; `sealed class HookAction` with `HookInstalled`, `HookUpdated`, `HookUpToDate`, `HookReplaced(backup)`, `HookRefused`, `HookRemoved`, `HookRestored(backup)`, `HookNotFound`, each carrying `hook` and `path`; `HookInstaller(HookStore store)` with `Future<List<HookAction>> install(Set<HookName> hooks, {required bool force})` and `Future<List<HookAction>> uninstall()`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('the script is exactly the text of specs/git.md section 7', () {
  expect(renderHookScript(HookName.preCommit), File('test/goldens/hooks/pre-commit.sh').readAsStringSync());
});
test('the script uses LF only and ends with one newline', () {
  final s = renderHookScript(HookName.prePush);
  expect(s.contains('\r'), isFalse); expect(s.endsWith('exit 0\n'), isTrue); expect(s, contains('run pre-push "\$@"'));
});
test('managed means the second line is the marker', () {
  expect(isManagedHook('#!/bin/sh\n# stagelatch:managed\n'), isTrue);
  expect(isManagedHook('#!/bin/sh\necho hi\n# stagelatch:managed\n'), isFalse);
});
// One test per cell of the matrix in specs/git.md section 8, for example:
test('install refuses an unmanaged hook and leaves it untouched', () async {
  store.files[HookName.preCommit] = '#!/bin/sh\nhusky\n';
  expect(await installer.install({HookName.preCommit}, force: false), [isA<HookRefused>()]);
  expect(store.files[HookName.preCommit], '#!/bin/sh\nhusky\n');
});
test('force backs up an unmanaged hook before replacing it', () async { /* HookReplaced(backup: 'pre-commit.stagelatch-backup') */ });
test('a second backup gets a numeric suffix', () async { /* 'pre-commit.stagelatch-backup.1' */ });
test('uninstall removes a managed hook and restores the newest backup', () async { /* [HookRemoved, HookRestored] */ });
test('uninstall never touches an unmanaged hook', () async { /* [HookNotFound] */ });
test('FileHookStore writes bytes verbatim and sets the executable bit', () async { /* mode check skipped on Windows */ });
test('FileHookStore refuses a hooks directory that resolves outside the repository and git directory', () async { /* S3 */ });
```

- [ ] **Step 2: Run.** Expected: FAIL, types undefined.
- [ ] **Step 3: Implement.** The template is one constant with a single `<hook>` placeholder. `FileHookStore` writes with `File.writeAsBytes` (never a text mode that could translate line endings), creates the directory if needed, and verifies containment after resolving symlinks.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(hooks): add managed hook script and safe installer`

### Task 13: Command-line interface and composition root

**Branch:** `feat/01-13-cli`

**Files:**
- Create: `lib/src/cli/runner.dart`, `composition.dart`, `io.dart`, `commands/init_command.dart`, `install_command.dart`, `uninstall_command.dart`, `run_command.dart`
- Create: `lib/src/application/init/project_detector.dart`, `config_writer.dart`; `lib/src/infrastructure/io/local_working_tree.dart`, `system_clock.dart`
- Modify: `bin/stagelatch.dart`, `test/support/temp_repo.dart` (add `stagelatch`)
- Test: `test/cli/runner_test.dart`, `init_command_test.dart`, `run_command_test.dart`, `test/application/init/project_detector_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: `Io({required StringSink stdout, required StringSink stderr, required Stream<List<int>> stdin, required Environment environment})`; `Future<int> runStagelatch(List<String> args, Io io)`; `Composition.create(Io io) -> Composition` exposing `pipeline`, `hookInstaller`, `git`, `close()`; `DetectedProject { usesFlutter, usesFvm, usesCodegen, usesL10n, usesAssets }` from `ProjectDetector(SnapshotFiles, Documents).detect()`; `String renderConfig(DetectedProject project, CheckCatalog catalog)`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('--version prints the version and exits 0', () async {
  expect(await run(['--version']), 0); expect(out.toString(), 'stagelatch 0.1.0-dev.1\n');
});
test('unknown command and unknown hook are usage errors', () async {
  expect(await run(['nope']), 64); expect(await run(['run', 'post-merge']), 64);
});
test('outside a work tree is a usage error with the exact message', () async {
  expect(await run(['run', 'pre-commit'], cwd: emptyDir), 64);
  expect(err.toString(), contains('Not inside a git work tree: '));
});
test('a blocking finding exits 1 and prints the report on stdout', () async { /* staged pubspec with ../x */ });
test('an internal error prints the four-line message and exits 70', () async {
  // composition with a check that throws
  expect(err.toString(), startsWith('stagelatch: internal error in check "boom": '));
  expect(err.toString(), contains('To proceed anyway: git commit --no-verify\n'));
});
test('invalid config exits 78 with file, line and column', () async { /* ... */ });
test('init writes a config that lists only checks of this version, then installs hooks', () async {
  expect(await run(['init']), 0);
  expect(await repo.read('stagelatch.yaml'), contains('pre-commit: [pubspec]'));
  expect(out.toString(), contains('Created stagelatch.yaml.\n'));
});
test('init refuses to overwrite without --force', () async {
  expect(await run(['init']), 64); expect(err.toString(), contains('stagelatch.yaml already exists. Use --force to overwrite.'));
});
test('init --no-hooks does not install', () async { /* ... */ });
test('install and uninstall print one line per hook as specified', () async { /* specs/cli.md 3.2, 3.3 */ });
test('-C runs in another directory', () async { /* ... */ });
```

- [ ] **Step 2: Run** `dart test test/cli`. Expected: FAIL, `runStagelatch` undefined.
- [ ] **Step 3: Implement.** `runStagelatch` is the only place with `catch (Object)`; it maps `StagelatchException` through `ExitCode.forException` and everything else to the internal error text of `specs/cli.md` section 2. `bin/stagelatch.dart` builds `Io` from `dart:io`, awaits `runStagelatch`, and sets `exitCode`. `composition.dart` is the single file that constructs infrastructure classes; it always closes the git processes in a `finally`. `renderConfig` writes the keys of `specs/config.md` section 2 that apply, with one comment line per section.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(cli): add init, install, uninstall and run pre-commit`

### Task 14: Acceptance suite for 0.1.0-dev.1

**Branch:** `test/01-14-acceptance`

**Files:**
- Create: `test/acceptance/ac01_partial_staging_test.dart` … `ac16_staged_config_test.dart`, `determinism_test.dart`
- Create: `test/support/shim.dart`

**Interfaces:**
- Consumes: `TempRepo.stagelatch`, the whole CLI.
- Produces: `Future<String> createShimDirectory()` returning a directory containing a `stagelatch` shell script (and `stagelatch.bat` on Windows) that runs `dart <repo>/bin/stagelatch.dart "$@"`, for the end-to-end hook tests.

- [ ] **Step 1: Write the scenarios AC-01 to AC-16** of `testing.md` section 4, one file each. They are written against existing code, so most pass at once; that is expected here. Each asserts exit code and the complete stdout. Key assertions:
  - AC-01: staged `pubspec.yaml` clean and working tree copy with `path: ../x` exits 0; the reverse exits 1.
  - AC-05: first commit with a violating pubspec exits 1.
  - AC-06: a violating pubspec merged in unchanged from the other branch exits 0; the same file edited during conflict resolution exits 1.
  - AC-08: with `core.hooksPath=.husky` and an existing `.husky/pre-commit`, `install` exits 64 and the file is unchanged; `install --force` writes the backup next to it.
  - AC-09: `install` run inside a linked worktree writes to the common hooks directory; a commit in the worktree triggers it.
  - AC-12: every command with stdin closed and `stdoutIsTerminal: false` terminates and its output contains no `\u001b`.
  - AC-13: `git commit` with the shim directory first on `PATH` and a violating pubspec fails, and the commit is not created. Runs on all three operating systems.
  - AC-14: `git commit` with a `PATH` that contains git and `sh` but no `stagelatch` and no `dart` succeeds, and stderr contains `stagelatch not found; skipping.`
  - AC-15: `git commit -a` and `git commit pubspec.yaml` with a violating working tree pubspec both fail.
  - Determinism: as in `testing.md` section 5.
- [ ] **Step 2: Run** `dart test test/acceptance`. Any failure is a defect in an earlier task: fix it in this branch with a unit test that reproduces it, and list it under "Deviations".
- [ ] **Step 3: If AC-13 fails on Windows,** correct the hook template in `specs/git.md` section 7 first, then the constant and its golden, until the Windows job is green. Record what Git for Windows actually resolved in the pull request.
- [ ] **Step 4: Run** all four commands on all matrix cells through CI. Expected: PASS.
- [ ] **Step 5: Commit.** `test: add acceptance scenarios for the pre-commit foundation`

### Task 15: Release plumbing and 0.1.0-dev.1

**Branch:** `ci/01-15-release`

**Files:**
- Create: `release-please-config.json`, `.release-please-manifest.json`, `.github/workflows/release-please.yaml`, `.github/workflows/publish.yaml`
- Modify: `README.md`, `CHANGELOG.md`, `pubspec.yaml` (description, topics), `docs/plans/README.md`

**Interfaces:**
- Produces: a tag `v<version>` on `main` triggers publishing through OIDC.

- [ ] **Step 1: Configure release-please** for a Dart package at the repository root, with `lib/src/version.dart` as an extra file, on branch `main`.
- [ ] **Step 2: Add `publish.yaml`** triggered by tags matching `v[0-9]+.[0-9]+.[0-9]+*`, with `permissions: id-token: write`, calling the Dart team's reusable publish workflow pinned by SHA.
- [ ] **Step 3: Write the README** for this version: what it is, install, `init`, what the two rules catch, the exit codes, and a "Status: pre-release" note. No benchmark yet.
- [ ] **Step 4: Verify** `dart pub publish --dry-run` reports no errors and no warnings.
- [ ] **Step 5: Commit.** `ci(release): add release-please and OIDC publishing`
- [ ] **Step 6: Release.** Open `develop` -> `main` as `release: 0.1.0-dev.1` (workflow section 8). **Stop here for the owner:** the first publish of the package name is manual (`dart pub publish` by the owner), followed by enabling automated publishing on pub.dev.

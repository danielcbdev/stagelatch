# Spike: Dart Toolchain Mechanism Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure two ways of producing diagnostics and formatting for an index snapshot, and choose one with numbers.

**Architecture:** A throwaway package under `benchmark/` holds two probes behind one interface, a parity oracle and a timing runner. Nothing from it is imported by `lib/`. Its outputs are a report and an amendment to ADR-0008.

**Tech Stack:** Dart 3.13, `package:analyzer`, `package:dart_style`, the SDK's analysis server (`dart language-server --protocol=analyzer`), git.

**Spec:** [`specs/dart-toolchain.md`](../specs/dart-toolchain.md) sections 4, 5 and 8; ADR-0008; `CLAUDE.md` roadmap item 0.

## Global Constraints

- `benchmark/` is its own package with its own `pubspec.yaml`. The root package gains no dependency from this plan.
- The corpus is a public repository pinned to a full commit SHA; setup is one command and needs no credentials.
- Timings are taken through the real distribution path: `dart pub global activate --source path benchmark`, then the activated executable. Never `dart run`, never `dart compile exe`.
- Analyzer caches are redirected to a temporary directory for cold runs. The user's own cache directory is never deleted.
- Each timing is reported as p50 and p95 over 10 warm runs, plus 3 cold runs, with machine and SDK versions recorded.
- Branches: `spike/00-<task>-<slug>`. One pull request per task into `develop`.
- This plan is exploratory: steps are measure-and-record, not test-first. Probe code still passes `dart analyze --fatal-infos`.

## Review Focus

- A probe that analyzes the working tree instead of the snapshot would look fast and be wrong: each probe must prove the overlay took effect (Task 2 and 3, step "prove the overlay").
- A warm run that reuses a server left alive by a previous run measures a daemon, not the tool: each run starts and stops its own processes.
- Parity that is only checked on a clean project hides diagnostics differences: the corpus scenario must contain at least one error, one warning, one lint and one unformatted file.
- An older project SDK is where the embedded candidate is most likely to diverge: parity is checked on two SDK versions.
- Timing the import graph on a small package says nothing: it is measured on the corpus's full file set.

---

### Task 1: Corpus, scenarios and package scaffold

**Branch:** `spike/00-01-corpus`

**Files:**
- Create: `benchmark/pubspec.yaml`, `benchmark/analysis_options.yaml`, `benchmark/README.md`
- Create: `benchmark/corpus.yaml`, `benchmark/bin/setup.dart`
- Create: `benchmark/scenarios/s3/`, `benchmark/scenarios/s10/` (each with `staged.patch`, `unstaged.patch`, `expected.md`)
- Modify: `.gitignore` (add `.benchmark/`)

**Interfaces:**
- Produces: `.benchmark/corpus/` (a checkout at the pinned SHA with `pub get` done); `Scenario { name, stagedPatch, unstagedPatch }` loaded by `loadScenario(String name)` in `benchmark/lib/scenario.dart`; `applyScenario(Scenario)` which resets the corpus, applies `staged.patch` with `git apply --cached` and `unstaged.patch` with `git apply`.

- [ ] **Step 1: Choose the corpus.** Criteria, all required: public; one Flutter package with at least 1,000 `.dart` files; resolves with `flutter pub get` on a current stable Flutter with no private dependency and no native build step; permissive license. Evaluate candidates in this order and take the first that passes: the Immich mobile app, the AppFlowy Flutter app, then any other large open-source Flutter app. Record the repository URL, SHA, package directory, Flutter version and file count in `corpus.yaml`. If no candidate passes, stop and ask the owner.
- [ ] **Step 2: Write `setup.dart`:** clone into `.benchmark/corpus`, check out the SHA, run `pub get` with the Flutter version named in `corpus.yaml`. Running it twice is a no-op.
- [ ] **Step 3: Author scenario `s3`:** three modified files in one feature directory. `staged.patch` introduces exactly one analyzer error, one warning, one lint and leaves one file unformatted. `unstaged.patch` edits a fourth file that one staged file imports, in a way that would add a different error if it were analyzed.
- [ ] **Step 4: Author scenario `s10`:** ten modified files, one of them imported by at least 100 other files. Same finding mix, same unstaged trap.
- [ ] **Step 5: Verify.** Run `dart run benchmark/bin/setup.dart` then apply each scenario; `git -C .benchmark/corpus status --short` shows the staged and unstaged paths listed in `expected.md`.
- [ ] **Step 6: Commit.** `chore(spike): add benchmark corpus and scenarios`

### Task 2: Probe A, embedded analyzer and formatter

**Branch:** `spike/00-02-probe-embedded`

**Files:**
- Create: `benchmark/lib/probe.dart`, `benchmark/lib/probe_embedded.dart`

**Interfaces:**
- Consumes: `Scenario`, `applyScenario`.
- Produces:

```dart
final class ProbeInput {
  String get repoRoot; String get packageRoot; String get sdkRoot;
  Map<String, String> get overlays;        // absolute path -> snapshot content
  List<String> get files;                  // absolute paths to diagnose
  List<String> get toFormat;               // absolute paths to format
}
final class ProbeDiagnostic { String get path; String get code; String get severity; int get offset; int get length; String get message; }
final class ProbeResult {
  List<ProbeDiagnostic> get diagnostics;   // sorted by path, offset, code
  Map<String, String> get formatted;       // path -> formatted text
  Map<String, Duration> get phases;        // 'start', 'overlay', 'diagnose', 'format'
}
abstract interface class Probe { String get name; Future<ProbeResult> run(ProbeInput input); }
```

- [ ] **Step 1: Implement `EmbeddedProbe`** with `AnalysisContextCollection`, an `OverlayResourceProvider` over the physical provider, and `sdkPath` set from the input. Diagnostics come from the session's per-file error query; formatting from `DartFormatter` with the file's language version and the page width from `analysis_options.yaml`. Confirm the exact API names against the pinned `analyzer` version's documentation before writing; record the version in the report.
- [ ] **Step 2: Prove the overlay.** Run on `s3`: the result must contain the staged error and must **not** contain the error that only exists in `unstaged.patch`. Then run with empty overlays and confirm the unstaged error appears. Record both outputs.
- [ ] **Step 3: Record phase timings** for `s3` and `s10` from a single in-process run (not yet the official numbers).
- [ ] **Step 4: Commit.** `chore(spike): add embedded analyzer probe`

### Task 3: Probe B, delegated analysis server

**Branch:** `spike/00-03-probe-delegated`

**Files:**
- Create: `benchmark/lib/probe_delegated.dart`, `benchmark/lib/server_client.dart`

**Interfaces:**
- Consumes: `Probe`, `ProbeInput`, `ProbeResult`.
- Produces: `DelegatedProbe implements Probe`; `ServerClient` with `start(String sdkRoot, {required String cacheDir})`, `request(String method, Map<String, Object?> params)`, `close()`.

- [ ] **Step 1: Implement `ServerClient`:** spawn `<sdk>/bin/dart language-server --protocol=analyzer --cache=<cacheDir>`; newline-delimited JSON requests with incrementing string ids; match responses by id; collect notifications.
- [ ] **Step 2: Implement `DelegatedProbe`:** `analysis.setAnalysisRoots` with the package root; `analysis.updateContent` with one `add` overlay per entry; `analysis.getErrors` per file; `edit.format` per file to format with `selectionOffset: 0, selectionLength: 0`, applying the returned edits. Shut the server down with `server.shutdown` in a `finally`. Confirm method and field names against the protocol specification shipped with the SDK in use.
- [ ] **Step 3: Prove the overlay**, exactly as in Task 2 step 2.
- [ ] **Step 4: Decide the wait strategy and record it:** whether `analysis.getErrors` may be sent immediately after `updateContent`, or must wait for a status notification. Measure both if both are correct.
- [ ] **Step 5: Record phase timings** for `s3` and `s10`.
- [ ] **Step 6: Commit.** `chore(spike): add delegated analysis server probe`

### Task 4: Parity oracle

**Branch:** `spike/00-04-parity`

**Files:**
- Create: `benchmark/lib/oracle.dart`, `benchmark/bin/parity.dart`

**Interfaces:**
- Consumes: both probes.
- Produces: `Future<ProbeResult> runOracle(ProbeInput)`; `List<String> diffResults(ProbeResult expected, ProbeResult actual)`, empty when identical.

- [ ] **Step 1: Implement the oracle.** Build a tree from the index (`git write-tree`), export it to a temporary directory with `git archive | tar -x`, copy `.dart_tool/package_config.json` and rewrite its relative roots to absolute, then run the corpus SDK's `dart analyze --format=json` and `dart format --output=show` there. Map results back to repository paths. Remove the directory in a `finally`.
- [ ] **Step 2: Implement `diffResults`:** compare diagnostics as the set of `(path, code, severity, offset, length)` restricted to the requested files, and formatted text byte for byte. One line per difference.
- [ ] **Step 3: Run `parity.dart`** for both probes on `s3` and `s10` with the corpus's pinned SDK. Record the diffs.
- [ ] **Step 4: Repeat on an older SDK:** install the previous stable Flutter minor with FVM, re-resolve the corpus if it supports it (otherwise use a small fixture project created for this purpose with an SDK constraint that fits), and record the diffs for both probes.
- [ ] **Step 5: Commit.** `chore(spike): add parity oracle`

### Task 5: Import graph timing

**Branch:** `spike/00-05-import-graph`

**Files:**
- Create: `benchmark/lib/directives_parse.dart`, `benchmark/lib/directives_scan.dart`, `benchmark/bin/graph.dart`

**Interfaces:**
- Produces: `List<String> directivesByParser(String source)` using `parseString`; `List<String> directivesByScanner(String source)` using a hand-written scanner that skips comments and strings and stops at the first declaration; both return directive URIs in source order.

- [ ] **Step 1: Implement both extractors.**
- [ ] **Step 2: Run over every `.dart` file of the corpus,** reading content through one `git cat-file --batch` by blob id. Record: file count, total time per extractor (cold process), and the number of files where the two disagree. List the disagreeing files.
- [ ] **Step 3: Record** the time to compute the transitive dependents of the widely imported file of `s10`.
- [ ] **Step 4: Commit.** `chore(spike): measure import graph construction`

### Task 6: Official measurements

**Branch:** `spike/00-06-measure`

**Files:**
- Create: `benchmark/bin/stagelatch_bench.dart` (the activated executable), `benchmark/bin/measure.dart`
- Create: `docs/spike/report.md`

**Interfaces:**
- Consumes: both probes, scenarios.
- Produces: `stagelatch_bench <probe> <scenario> --cache <dir>` prints one JSON line with `phases` and `totalMs`, where `totalMs` is measured by the caller from process start to exit.

- [ ] **Step 1: Activate:** `dart pub global activate --source path benchmark`. Confirm with `dart pub global list`.
- [ ] **Step 2: Cold runs.** For each probe and scenario, 3 runs, each with a fresh empty `--cache` directory and after one unrelated `dart --version` call.
- [ ] **Step 3: Warm runs.** For each probe and scenario, 10 consecutive runs sharing one `--cache` directory, discarding the first.
- [ ] **Step 4: Write `docs/spike/report.md`** with: machine, OS, Dart and Flutter versions, corpus identity, `analyzer` and `dart_style` versions; a table of cold and warm p50/p95 per probe and scenario with the phase breakdown; the parity results of Task 4; the import graph numbers of Task 5; the overlay proofs.
- [ ] **Step 5: Commit.** `docs(spike): record latency and parity measurements`

### Task 7: Decision

**Branch:** `spike/00-07-decision`

**Files:**
- Modify: `docs/spike/report.md` (add "Decision"), `docs/adr/0008-parity-with-the-project-sdk.md`, `docs/specs/dart-toolchain.md` (section 8), `docs/engineering/coding-standards.md` (dependency table), `docs/plans/02-core.md` (Tasks 6 and 7), `CLAUDE.md`

- [ ] **Step 1: Apply the gates.**
  - **G1, parity:** zero differences on both scenarios and both SDK versions. A candidate that fails G1 is eliminated.
  - **G2, latency:** warm p50 of the whole process on `s10` at or below 2.0 s.
- [ ] **Step 2: Choose.** Among candidates that pass G1 and G2, take the lower warm p50 on `s10`. If the two are within 15% of each other, take B, because it has no analyzer version coupling. If a candidate passes G1 but none passes G2, write a "Daemon evaluation" section (what would stay alive, how it is started and stopped, what it costs in complexity) and **stop: ask the owner**. If none passes G1, stop and ask the owner.
- [ ] **Step 3: Decide the fact extractor** from Task 5: use `parseString` unless the scanner is at least 5 times faster on the corpus and the two never disagree.
- [ ] **Step 4: Record the decision** in the report and amend ADR-0008: status `Accepted`, the mechanism, the numbers, the resulting SDK floor and dependency list. Update the other files listed above so that no document still calls the mechanism undecided.
- [ ] **Step 5: Commit.** `docs(adr): select the Dart toolchain mechanism`
- [ ] **Step 6: Gate.** The owner approves this pull request before plan 02 starts.

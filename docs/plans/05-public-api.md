# Public API (1.0.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status: done (1.0.0).** Spec [`custom-checks.md`](../specs/custom-checks.md) and [ADR-0019](../adr/0019-custom-checks-out-of-process.md) are Approved. Stability contract frozen; `v1.0.0` published.

**Goal:** Ship `1.0.0`: custom checks out of process, and a frozen stability contract.

**Architecture:** A custom check is a verify-phase `Check` (`ExternalCheck`) that forwards to a child over line-delimited JSON (`protocol: 1`). Filtering, suppression, baseline and reporters stay unchanged once findings are mapped. No separate `stagelatch_core` package; author kit is `example/custom_check/` plus `docs/custom-checks.md`.

**Tech Stack:** As plan 04. Process host in `infrastructure/custom/`; protocol types in `application/custom/`.

**Spec:** [`specs/custom-checks.md`](../specs/custom-checks.md). **ADR:** [0019](../adr/0019-custom-checks-out-of-process.md). **Stability:** [`docs/stability.md`](../stability.md) (Binding; freeze in Task 7 Phase 3).

## Global Constraints

- Everything in the Global Constraints of plans 01–04.
- S1 exception and S14b exactly as [`security.md`](../engineering/security.md) and ADR-0019: argument list from `custom_checks.<id>.run`, never a shell; resolved SDK for `dart`/`flutter`; Windows `.bat` guard.
- Content only through protocol `read` (snapshot/base). Source closure must be non-empty (explicit `sources` when inference fails → exit 78). Divergence → exit 64 (usage; never a silent pass). Bare `run[0]` resolved via explicit PATH walk to an absolute path (AC-36).
- Timeout default 60s → kill + exit 70; distinct from `time_budget` (ADR-0003).
- One process per `ExternalCheck.run`; kill/await in `finally`.
- After 1.0.0, a breaking change to a §1 artefact of `stability.md` requires a major version.

## Review Focus

- **A child that prints non-protocol text to stdout** (a stray `print`). Expected: protocol error naming the check and showing the offending line, truncated to 200 sanitized characters; exit 70.
- **A child that never answers.** Expected: timeout, child killed, exit 70; no orphan process.
- **A child that reports a rule it did not declare, or a path outside the repository.** Expected: protocol error; exit 70; the finding is not kept.
- **A custom check ID equal to a built-in one.** Expected: config error at load time (exit 78).
- **Source closure diverges** (unstaged edit to the check entry). Expected: no child started; exit 64 naming the check and path with the entry-point message from `custom-checks.md` §6.
- **`run` that cannot infer sources** (e.g. `python tool/x.py`, `dart run package:…`) without `sources`. Expected: exit 78 with `custom_checks."<id>": cannot infer a non-empty source closure from "run"; set "custom_checks.<id>.sources" to a non-empty list.`
- **A pull request from a fork running `ci`.** Expected: documented risk, and `--no-custom-checks` works.
- **Findings for a path inside the repo but outside the changeset.** Expected: accepted, then normal filters apply.

### What changed and why (Task 1 rewrite)

| Change | Why | Source |
|---|---|---|
| Spec Draft → Proposed; ADR-0019; `stability.md` draft | Gate before any production code | brief, CLAUDE.md roadmap |
| No `stagelatch_core` in 1.0.0; kit = guide + `example/` | Release overhead vs benefit; CLAUDE.md said evaluate | ADR-0004, measurement not needed |
| Protocol 1: text `read` only | Avoid coupling to facts schema | ADR-0013/0017 |
| One process per invocation; timeout 60s → exit 70 | Hang ≠ budget skip; keep-alive complexity | ADR-0003, S14 |
| Working tree + diverge → exit 64 | Silent pass forbidden; usage not internal error (owner) | ADR-0018 tension resolved |
| Default pre-push/ci only | Cold `dart run` 0.66 s + tool ~0.8 s blows pre-commit budget | measurement |
| Tasks 2–7 signatures aligned to Proposed spec | Binding interfaces for implementers | architecture §5.8 |
| AC-29–AC-36 in `testing.md` | Acceptance coverage for protocol, diverge (64), PATH cwd plant, Windows, forks | testing.md pattern |

---

### Task 1: Design review (gate)

**Branch:** `docs/05-01-design-review`

**Files:**
- Modify: `docs/specs/custom-checks.md`, this plan, `docs/engineering/security.md`, `docs/engineering/testing.md`, `docs/architecture.md`, `docs/adr/README.md`, `docs/specs/README.md`, `docs/plans/README.md`, `CLAUDE.md`
- Create: `docs/adr/0019-custom-checks-out-of-process.md`, `docs/stability.md`

- [x] **Step 1: Answer the open questions** (section 8 of the old draft + brief 1.1) with alternatives, recommendation and decider.
- [x] **Step 2: Rewrite the spec** from Draft to Proposed.
- [x] **Step 3: Write ADR-0019** and amend S1/S14.
- [x] **Step 4: Revise Tasks 2–7** and add AC-29+.
- [x] **Step 5: Stop.** Owner approves this pull request before Task 2. Approved on 2026-11-21, with four adjustments applied in the same pull request (#87).

---

### Task 2: Protocol codec

**Branch:** `feat/05-02-protocol-codec`

**Files:**
- Create: `lib/src/application/custom/protocol.dart`, `protocol_codec.dart`
- Test: `test/application/custom/protocol_codec_test.dart`

**Interfaces:**
- Consumes: nothing new from prior tasks.
- Produces:

```dart
sealed class ToCheck {}
final class InitMessage implements ToCheck {
  InitMessage({required int protocol, required EntryKind entry, required Map<String, Object?> settings, List<String> capabilities = const []});
}
final class RunMessage implements ToCheck {
  RunMessage({required List<FileChange> changes, required bool all});
}
final class ContentMessage implements ToCheck {
  ContentMessage({required int id, String? text});
}

sealed class FromCheck {}
final class ReadyMessage implements FromCheck {
  ReadyMessage({required int protocol, required List<RuleDescriptor> rules});
}
final class ReadMessage implements FromCheck {
  ReadMessage({required int id, required RepoPath path, required String side}); // side: snapshot|base
}
final class FindingMessage implements FromCheck {
  FindingMessage({required RuleId rule, required RepoPath path, required int line, required int column, required String message});
}
final class DoneMessage implements FromCheck { const DoneMessage(); }

String encodeToCheck(ToCheck message);
FromCheck decodeFromCheck(String line); // throws ProtocolException
final class ProtocolException implements Exception {
  ProtocolException(this.reason, {this.line});
  final String reason;
  final String? line;
}
const int maxProtocolLineBytes = 1 << 20; // 1 MiB
```

- [x] **Step 1: Write the failing tests:** round trip of every message; unknown `type`; missing field; wrong field type; non-JSON; line over size limit; protocol version mismatch; rule id with wrong check segment rejected at host mapping time (codec accepts structurally valid JSON).
- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement** with pattern matching over decoded maps; no `as`.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(custom): add custom check protocol codec`

---

### Task 3: Process host

**Branch:** `feat/05-03-process-host`

**Files:**
- Create: `lib/src/application/ports/check_process.dart`, `lib/src/infrastructure/custom/spawned_check_process.dart`, `lib/src/application/custom/external_check.dart`, `test/support/fake_check_process.dart`
- Create: `test/fixtures/custom_checks/` (well-behaved, noisy, hanging, lying, outside-path)
- Test: `test/application/custom/external_check_test.dart`, `test/infrastructure/custom/spawned_check_process_test.dart`
- Modify: `docs/architecture.md` §5.8 if signatures drift (list under Deviations)

**Interfaces:**
- Consumes: Task 2 codec; `CheckContext.divergentAmong`; `SnapshotFiles`; `ResolvedSdk` / SDK locator via composition.
- Produces:

```dart
abstract interface class CheckProcess {
  Stream<String> get lines;
  void send(String line);
  Future<void> kill();
  Future<int> get exitCode;
}
abstract interface class CheckProcessFactory {
  Future<CheckProcess> start(List<String> command, {required String workingDirectory});
}
final class ExternalCheck implements Check {
  ExternalCheck({
    required String id,
    required List<String> command,
    required CheckProcessFactory factory,
    required Duration timeout,
    required Set<RepoPath> sourceClosure,
    Map<String, Object?> settings = const {},
  });
  // phase == verify; hasDynamicRules == true after ready (rules from child)
}
```

- Resolve `dart`/`flutter` to the resolved SDK before `start`. Bare `run[0]` → explicit PATH walk (skip empty/`.`/relative/in-repo), absolute path to `Process.start` (AC-36). Apply Windows `.bat` argument guard. Divergence before start and after exit → usage error (exit 64). Max 10_000 findings. Stderr cap 64 KiB.

- [x] **Step 1: Write the failing tests:** handshake and declared rules; `read` from snapshot with `text: null` for unreadable; findings mapped; each Review Focus case; child killed in `finally`; timeout; diverge → no start.
- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement.**
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(custom): run custom checks as child processes`

---

### Task 4: Config and registry integration

**Branch:** `feat/05-04-config-registry`

**Files:**
- Modify: `lib/src/application/config/config.dart`, `config_loader.dart`, `lib/src/application/pipeline/check_registry.dart`, `schema/stagelatch.schema.json`, `docs/specs/config.md`, `lib/src/cli/composition.dart`
- Test: `test/application/config/custom_checks_config_test.dart`, `test/application/pipeline/dynamic_registry_test.dart`

**Interfaces:**
- Produces: `CustomCheckConfig { String id; List<String> run; Duration timeout; List<RepoPath> sources; Map<String, RuleLevel> rules; Map<String, Object?> settings }`; `Config.customChecks`; `CheckRegistry.withCustom(List<ExternalCheck>)`; remove reserved-key rejection for `custom_checks` on tools ≥ 1.0.0.

- [x] **Step 1: Write the failing tests:** key loads; shadowing built-in → config error; `run` non-empty list of strings; selector and `rules:` may name a custom rule; deferred unknown-rule validation; default timeout 60s; explicit empty `sources` → exit 78; omitted `sources` when `run` is not inferable (e.g. `python`, `dart run package:…`) → exit 78 with the empty-closure message from `custom-checks.md` §5/§6; additional keys land in `settings`.
- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement.**
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(config): add custom_checks`

---

### Task 5: Operational safeguards

**Branch:** `feat/05-05-safeguards`

**Files:**
- Modify: `lib/src/cli/commands/ci_command.dart`, `run_command.dart`, `lib/src/application/doctor/doctor.dart`, `docs/specs/cli.md`
- Test: `test/cli/no_custom_checks_test.dart`, `test/application/doctor/custom_checks_probe_test.dart`
- Acceptance: AC-32 (`--no-custom-checks`)

- [x] **Step 1: Write the failing tests:** `--no-custom-checks` skips and notices; `doctor` lists each custom check and resolved command; with the flag, ignore whose check prefix is a configured custom id is accepted without handshake; unknown check prefix still yields `invalid-ignore`; with check active, undeclared rule yields `invalid-ignore`.
- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement.**
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(cli): add --no-custom-checks and doctor listing`

---

### Task 6: Author experience

**Branch:** `feat/05-06-author-kit`

**Files:**
- Create: `docs/custom-checks.md`, `example/custom_check/README.md`, `example/custom_check/bin/check.dart` (and minimal supporting files)
- Test: `test/acceptance/ac34_example_custom_check_test.dart` (or fixture-driven end-to-end against the example)

- [x] **Step 1: Write the failing tests:** the example check passes the well-behaved host assertions end to end (init/ready/run/done; optional finding).
- [x] **Step 2: Run.** Expected: FAIL.
- [x] **Step 3: Implement** the guide and example: write a rule, test it, wire it in config.
- [x] **Step 4: Run** all four commands. Expected: PASS.
- [x] **Step 5: Commit.** `feat(custom): add author guide and example check`

---

### Task 7: Freeze and 1.0.0

**Branch:** `docs/05-07-freeze` (freeze); `release/1.0.0` (Phase 4)

**Files:**
- Modify: `docs/stability.md` (Draft → binding), `README.md`, `docs/plans/README.md`, `action.yml` (document `--no-custom-checks` / fork note), `docs/engineering/workflow.md` (post-1.0 break marking)
- Create: `test/compat/1.0/` fixtures and tests per `stability.md` §1 (config keys/types/rejects/exit 78 — not validation message text; hook marker + invocation contract — not full script bytes)
- Modify: `lib/stagelatch.dart` only if comments need updating (still exports `packageVersion` only)

- [x] **Step 1: Finalize `docs/stability.md`** and add `test/compat/1.0/` tests matching §1 (no byte-compare of hook template; no exact config validation strings).
- [x] **Step 2: Verify** all four commands and `dart pub publish --dry-run`.
- [x] **Step 3: Acceptance AC-29–AC-35 green on the matrix where applicable.
- [x] **Step 4: Commit.** `docs: define the 1.0 stability contract`
- [x] **Step 5: Release** `1.0.0` per [`workflow.md`](../engineering/workflow.md) section 8 (`release-as: 1.0.0` as needed). Phase 4 complete: `v1.0.0` tagged and on pub.dev.

---

## Order

**1 → 2 → 3 → 4 → 5 → 6 → 7** (strict). Task 1 is the gate. Task 6 may start after Task 3 (needs a working host) but must not merge before Task 5 if it documents `--no-custom-checks`; prefer after 5.

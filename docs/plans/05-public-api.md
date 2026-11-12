# Public API (1.0.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status: Draft.** This plan implements a spec that is itself a draft. Task 1 is a gate: nothing after it starts until the owner re-approves the spec. Signatures below are the current intent and will be revised in Task 1.

**Goal:** Ship `1.0.0`: custom checks that run out of process, and a frozen, documented contract.

**Architecture:** A custom check is a `Check` whose implementation forwards to a child process over line-delimited JSON. From the pipeline's point of view it is indistinguishable from a built-in verify-phase check, so filtering, suppression, baseline and reporting need no change.

**Tech Stack:** As plan 04. Possibly a second package, `stagelatch_core`, decided in Task 1.

**Spec:** [`specs/custom-checks.md`](../specs/custom-checks.md) (draft).

## Global Constraints

- Everything in the Global Constraints of plans 01–04.
- The exception to S1 is exactly the one in `custom-checks.md` section 5: an argument list from `custom_checks.<id>.run`, never a shell.
- A custom check reads files only through the protocol's `read` message, so it sees the snapshot.
- Any protocol violation, crash or timeout is an internal error naming the check (exit 70). It is never a silent pass.
- After 1.0.0, a breaking change to the config schema, a rule ID, an exit code, the JSON report schema or the protocol requires a major version.

## Review Focus

- **A child that prints non-protocol text to stdout** (a stray `print`). Expected: protocol error naming the check and showing the offending line, truncated.
- **A child that never answers.** Expected: timeout, child killed, exit 70; no orphan process.
- **A child that reports a rule it did not declare, or a path outside the repository.** Expected: protocol error; the finding is not reported.
- **A custom check ID equal to a built-in one.** Expected: config error at load time.
- **A pull request from a fork running `ci`.** Expected: documented risk, and `--no-custom-checks` works.

---

### Task 1: Design review (gate)

**Branch:** `docs/05-01-design-review`

**Files:**
- Modify: `docs/specs/custom-checks.md`, this plan, `docs/adr/` (new ADR for the process protocol and the S1 exception)

- [ ] **Step 1: Answer the open questions** of `custom-checks.md` section 8 with what 0.1–0.3 taught: whether `stagelatch_core` is a separate package, whether facts are served over the protocol, process lifetime, timeout default.
- [ ] **Step 2: Rewrite the spec** from "Draft" to "Proposed", with the final message schemas and exact error messages.
- [ ] **Step 3: Write the ADR.**
- [ ] **Step 4: Revise Tasks 2–7** of this plan to the final signatures.
- [ ] **Step 5: Stop.** The owner approves the pull request before Task 2.

### Task 2: Protocol codec

**Branch:** `feat/05-02-protocol-codec`

**Files:**
- Create: `lib/src/application/custom/protocol.dart`, `protocol_codec.dart`
- Test: `test/application/custom/protocol_codec_test.dart`

**Interfaces:**
- Produces: `sealed class ToCheck` (`InitMessage`, `RunMessage`, `ContentMessage`) and `sealed class FromCheck` (`ReadyMessage`, `ReadMessage`, `FindingMessage`, `DoneMessage`); `String encodeToCheck(ToCheck)`; `FromCheck decodeFromCheck(String line)` throwing `ProtocolException(String reason, String line)`.

- [ ] **Step 1: Write the failing tests:** round trip of every message; unknown `type`; missing field; wrong field type; a line that is not JSON; a line over the size limit; protocol version mismatch.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** with pattern matching over decoded maps; no `as`.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(custom): add custom check protocol codec`

### Task 3: Process host

**Branch:** `feat/05-03-process-host`

**Files:**
- Create: `lib/src/application/ports/check_process.dart`, `lib/src/infrastructure/custom/spawned_check_process.dart`, `lib/src/application/custom/external_check.dart`, `test/support/fake_check_process.dart`
- Create: `test/fixtures/custom_checks/` (well-behaved, noisy, hanging, lying)
- Test: `test/application/custom/external_check_test.dart`, `test/infrastructure/custom/spawned_check_process_test.dart`

**Interfaces:**
- Produces: `CheckProcess { Stream<String> get lines; void send(String line); Future<void> kill(); Future<int> get exitCode }`; `CheckProcessFactory { Future<CheckProcess> start(List<String> command, {required String workingDirectory}) }`; `ExternalCheck({required String id, required List<String> command, required CheckProcessFactory factory, required Duration timeout}) implements Check`.

- [ ] **Step 1: Write the failing tests:** handshake and declared rules; `read` served from the snapshot, with `text: null` for unreadable files; findings mapped to `Finding` with the declared rule; each Review Focus case; the child is killed in a `finally`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** The command is started with an argument list (S1) in the repository root.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(custom): run custom checks as child processes`

### Task 4: Config and registry integration

**Branch:** `feat/05-04-config-registry`

**Files:**
- Modify: `lib/src/application/config/config.dart`, `config_loader.dart`, `lib/src/application/pipeline/check_registry.dart`, `schema/stagelatch.schema.json`, `docs/specs/config.md`
- Test: `test/application/config/custom_checks_config_test.dart`, `test/application/pipeline/dynamic_registry_test.dart`

**Interfaces:**
- Produces: `CustomCheckConfig { String id; List<String> run; Map<String, RuleLevel> rules }`; `Config.customChecks`; `CheckRegistry.withCustom(List<ExternalCheck>)`.

- [ ] **Step 1: Write the failing tests:** the key loads; an ID that shadows a built-in is a config error; `run` must be a non-empty list of strings; a selector and a `rules:` entry may name a custom rule; `stagelatch:ignore` accepts a custom rule ID.
- [ ] **Step 2: Run.** Expected: FAIL (the loader still rejects `custom_checks`).
- [ ] **Step 3: Implement.** Rule validation for custom IDs is deferred until the handshake declares them.
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(config): add custom_checks`

### Task 5: Operational safeguards

**Branch:** `feat/05-05-safeguards`

**Files:**
- Modify: `lib/src/cli/commands/ci_command.dart`, `run_command.dart`, `lib/src/application/doctor/doctor.dart`, `docs/engineering/security.md`
- Test: `test/cli/no_custom_checks_test.dart`, `test/application/doctor/custom_checks_probe_test.dart`

- [ ] **Step 1: Write the failing tests:** `--no-custom-checks` skips them and says so in a notice; `doctor` lists each custom check and its command; the security document's S1 names the exception.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** all four commands. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(cli): add --no-custom-checks and doctor listing`

### Task 6: Author experience

**Branch:** `feat/05-06-author-kit`

**Files:** as decided in Task 1: either `packages/stagelatch_core/` (protocol loop, `CustomCheck` base class, a test harness) or `docs/custom-checks.md` with a reference implementation under `example/`.

- [ ] **Step 1: Write the failing tests:** a sample check written with the kit passes the well-behaved fixture's assertions end to end.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the kit and a walkthrough: write a rule, test it, wire it in config.
- [ ] **Step 4: Run** all four commands (and the kit's own, if it is a package).
- [ ] **Step 5: Commit.** `feat(custom): add author kit and guide`

### Task 7: Freeze and 1.0.0

**Branch:** `docs/05-07-release`

**Files:**
- Create: `docs/stability.md`
- Modify: `README.md`, `lib/stagelatch.dart`, `docs/plans/README.md`

- [ ] **Step 1: Write `docs/stability.md`:** what is covered by semantic versioning (config schema, rule IDs, exit codes, JSON schema, protocol) and what is not (console text, timings, internal Dart API).
- [ ] **Step 2: Add compatibility tests** that load a frozen 1.0 config, baseline and protocol transcript from `test/compat/1.0/`; they must keep passing in every later release.
- [ ] **Step 3: Verify** all four commands and `dart pub publish --dry-run`.
- [ ] **Step 4: Commit.** `docs: define the 1.0 stability contract`
- [ ] **Step 5: Release** `1.0.0` per workflow section 8.

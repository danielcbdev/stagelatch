# Custom checks specification (1.0.0)

Status: **Proposed.** Awaiting owner approval (plan 05, Task 1 / Parada 1). Replaces the 2026-11-12 draft. Decision record: [ADR-0019](../adr/0019-custom-checks-out-of-process.md).

## 1. Goal

Let a team add its own rules, reported, filtered, suppressed and baselined exactly like built-in ones, without stagelatch entering the project's dependency graph (ADR-0004).

## 2. Constraint that drives the design

The tool runs from a global activation. It cannot `import` code from the project it checks, and the project cannot depend on the tool without bringing back the version conflicts ADR-0004 avoids. So a custom check must run in **its own process**.

## 3. Shape

- A custom check is an executable started by stagelatch that speaks a line-delimited JSON protocol on stdin and stdout.
- The protocol is the public contract. In 1.0.0 there is **no** separate `stagelatch_core` package: the author guide and a reference implementation under `example/custom_check/` show how to speak it. A helper package may be evaluated after 1.0.0 if demand warrants it.
- Declaration in config:

```yaml
custom_checks:
  team:
    run: [dart, run, tool/stagelatch_checks.dart]
    # timeout: 60s          # optional; default 60s
    # sources: [tool/stagelatch_checks.dart]  # optional when inferable; required when not (section 6)
    rules:
      no-print: error
```

- The check id is the map key (`team`). Rule IDs are `<check>/<rule>` like any other: `team/no-print`.
- A custom check id may not equal a built-in check id (`format`, `analyze`, `codegen`, `pubspec`, `l10n`, `assets`, `sensitive-files`, `tests`, `stagelatch`). Config load fails with exit 78: `custom_checks."<id>" shadows the built-in check "<id>".`
- Custom checks are verify-phase only. They cannot produce fixes in 1.0.0.
- Protocol version is `1`. A future major may introduce `protocol: 2`.

## 4. When they run

| Entry | Default | Override |
|---|---|---|
| `pre-push` | Each configured custom check runs when selected by `hooks.pre-push` (see below) | — |
| `ci` | Same via `hooks.ci` (default: union of pre-commit and pre-push) | `--no-custom-checks` skips all custom checks and prints a notice |
| `pre-commit` | **Not** in the built-in default hook lists | A team may list a custom check id in `hooks.pre-commit`; documented as opt-in and usually over budget (section 15) |
| `baseline create`, `baseline prune` | Run the pipeline **with** custom checks (they need findings for the baseline; see §12) | — |
| `doctor`, `why`, `init`, `install`, `uninstall` | Never start a custom-check process | — |

Selectors: a hook list may name a custom check by its id (`team`) or a rule (`team/no-print`), same vocabulary as built-ins (ADR-0009). Omitting custom checks from every hook list means they never run even if declared under `custom_checks:`.

`init` does not add custom check ids to generated hook lists.

## 5. Config schema

Under the root key `custom_checks` (a map). Each entry:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `run` | non-empty list of strings | (required) | Executable and arguments. Never a shell string. |
| `timeout` | duration | `60s` | Wall-clock budget for the child from spawn until `done` or failure. Kill + exit 70 when exceeded. Distinct from `time_budget` (ADR-0003). |
| `sources` | non-empty list of repository-relative paths | inferred when possible (section 6) | Files that constitute the check program for the divergence test. Required (exit 78) when inference cannot produce a non-empty closure. An explicit empty list is always a config error. |
| `rules` | map of `<rule>` → `error` \| `warning` \| `off` | `{}` | Severity overrides for this check's rules. Same semantics as the root `rules:` map; either place may set a level. Omitted rules keep the level the child declares as default severity `error`, unless the root `rules:` map says otherwise. |
| *(additional keys)* | any JSON-compatible YAML | (none) | Collected into `settings` and sent on `init` (§10.1). Must not reuse the reserved keys above. |

Validation at load time (exit 78):

| Problem | Message |
|---|---|
| ~~`custom_checks` present before 1.0.0~~ | Removed on develop: the feature lands before `packageVersion` is bumped to 1.0.0 via release-as; keeping the gate blocked tests. Published 1.0.0 tools accept the key; older published tools still reject it. |
| Entry id shadows a built-in | `custom_checks."<id>" shadows the built-in check "<id>".` |
| `run` missing, empty, or not a list of strings | `"custom_checks.<id>.run" must be a non-empty list of strings, found <actual>.` |
| `timeout` invalid | `Invalid duration "<value>" in "custom_checks.<id>.timeout".` |
| `sources` set to an empty list | `"custom_checks.<id>.sources" must be a non-empty list of repository paths when set, found an empty list.` |
| `sources` entry not a valid repository path | `Invalid path "<value>" in "custom_checks.<id>.sources".` |
| Rule key under `custom_checks.<id>.rules` contains `/` | `Rule name "<name>" under custom_checks."<id>" must not contain "/".` |
| Inference yields an empty closure and `sources` is missing | `custom_checks."<id>": cannot infer a non-empty source closure from "run"; set "custom_checks.<id>.sources" to a non-empty list.` |

Rule ids that appear only under `custom_checks.*.rules` or in selectors are **not** fully validated at load time: the child declares the live set at handshake. A selector or root `rules:` entry that names `<custom-id>/<rule>` is accepted syntactically when `<custom-id>` is a configured custom check; an unknown rule for that check becomes a finding or protocol error at run time (section 11), not a config error at load.

## 6. Where the check code comes from

The child is started with working directory = repository root. Its program bytes come from the **working tree** (and whatever the executable resolves on disk). File content the check analyzes must come **only** through the protocol `read` message, which serves the **snapshot**.

### Divergence closure

Before starting the child, and again after it exits (same pattern as ADR-0018), the host computes a **source closure** for the check. An empty closure is never allowed: that would skip the divergence test and weaken fail-closed.

1. If `sources` is set and non-empty: those paths (must exist in the snapshot as regular files, or the run is exit 70: `custom check "<id>": source "<path>" is missing from the snapshot.`).
2. If `sources` is set to an empty list: config error at load (exit 78) with the message in §5.
3. If `sources` is omitted, inference:
   - If `run[0]` is `dart` or `flutter` (exact) and some later argument is a repository-relative path ending in `.dart` that exists in the snapshot, that path is the entry.
   - Else if `run[0]` is a repository-relative path that exists in the snapshot, that path is the entry.
   - Else: inference failed. **Do not start the child.** Config error (exit 78), at load when detectable without a snapshot, otherwise before spawn:

```
custom_checks."<id>": cannot infer a non-empty source closure from "run"; set "custom_checks.<id>.sources" to a non-empty list.
```

   Examples that need explicit `sources`: `run: [python, tool/x.py]`, `run: [dart, run, package:some_pkg/bin/check.dart]`.
4. When the entry is a `.dart` file: add every `.dart` file in its transitive `import` / `export` / `part` closure that exists in the snapshot (same edge rules as the import graph), plus the owning package's `pubspec.yaml`, `analysis_options.yaml`, and `pubspec.lock` when that lock exists in the snapshot.

A path in the closure is **divergent** by the same three rules as ADR-0018 (snapshot vs working tree; untracked non-ignored import target; untracked non-ignored `analysis_options.yaml`).

### On diverge

**Do not start the child** (or, on the post-run check, discard its findings). The run ends with a **usage error** (exit **64**), not an internal error: uncommitted check sources are user state, not a tool bug.

Exact messages (one path listed; first divergent path wins):

| Entry | Message |
|---|---|
| `pre-commit` | `custom check "<id>": source diverges from the snapshot at <path>. Stage the check source changes, or pass --no-custom-checks.` |
| `pre-push` | `custom check "<id>": source diverges from the snapshot at <path>. Commit the check source changes or check out the pushed revision, or pass --no-custom-checks.` |
| `ci` (and any other entry that runs the pipeline with custom checks, including `baseline create` / `prune`) | `custom check "<id>": source diverges from the snapshot at <path>. Commit or discard local changes so the working tree matches the snapshot, or pass --no-custom-checks.` |

Silent pass is forbidden. This is stricter than `tests/affected` (warning skip): an opted-in custom gate must not be skipped while the push or CI run still reports success. Consequence: pushing a branch that is not checked out typically fails (exit 64) when custom checks are selected; check out that branch, or rely on `ci` (where the checkout matches HEAD).

## 7. Which executable

1. `run` is a non-empty argument list. Started with `Process.start` / equivalent: **never** a shell (`runInShell: false`). Exception to S1: the executable is named by config (ADR-0019).
2. If `run[0]` is `dart` or `flutter` (exact ASCII match): replace it with the corresponding binary of the **resolved project SDK** (ADR-0008 order: `sdk_path`, FVM, PATH). The resolved SDK must still satisfy S2 (outside the repository).
3. Otherwise, when `run[0]` has **no** path separator: resolve it **explicitly** against `PATH` entries, then pass the **absolute** path to `Process.start`. Skip empty entries, `.`, any relative entry, and any directory whose real path is **inside the repository**. Reason: on Windows, `CreateProcessW` searches the parent process current directory before `PATH` when the name has no separator ([CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)); hooks typically use cwd = repository root, so a planted `python.exe` / `x.bat` at the root would otherwise run. Dart's `Process.start` inherits that behaviour for bare names. Acceptance: AC-36 (Windows — executable planted at repo root must not run).
4. When `run[0]` contains a path separator: resolve relative to the repository root (must stay inside the repository after symlink resolution) or use as an absolute path when absolute. A missing executable is exit 70: `custom check "<id>": cannot start: <os message>`.
5. Working directory: repository root. Environment: inherited unchanged (S11). Stdin is the protocol; the host never leaves stdin open for interactive prompts (ADR-0011).
6. Windows: if the resolved executable path ends in `.bat` or `.cmd`, the S14 metacharacter rule applies to **every** argument: if any argument contains a control character or one of `"`, `&`, `|`, `<`, `>`, `^`, `%`, `!`, the run is exit 70 naming the check and the offending argument (truncated). Test plan: acceptance on Ubuntu, macOS and Windows (AC-33).

## 8. Process lifetime and concurrency

- **One process per pipeline invocation of that check.** Each call to `ExternalCheck.run` starts a fresh child and always kills/awaits it in a `finally`. No keep-alive across checks, across pre-push refs, or across pipeline phases.
- Custom checks run in the **verify** phase alongside other verify checks. The existing scheduler may run verify checks concurrently; each custom check has its own child. They do not share stdin/stdout.
- A pre-push with several refs runs the pipeline once per ref; each run gets its own children.
- Killing the child does not walk the process tree (same limitation as S14 / Flutter). Stdin is closed when the host is done sending.

## 9. Timeout vs time budget

| Mechanism | Config | On exceed | Verdict |
|---|---|---|---|
| `time_budget` | root key | Notice only | Unchanged (ADR-0003) |
| `custom_checks.<id>.timeout` | per check, default `60s` | Child killed; exit 70 | Fail closed |

Timeout message:

```
custom check "<id>": timed out after <duration>.
```

Hang-kill is not a time-budget skip. A slow machine that finishes before timeout still gets a full verdict; only an actual hang/limit triggers exit 70.

## 10. Protocol

Every message is one JSON object on one line, UTF-8, no pretty-print. Unknown fields on a known `type` are ignored (forward compatible). Unknown `type` is a protocol error.

### 10.1 Messages

| Direction | Schema | Purpose |
|---|---|---|
| tool → check | `{"type":"init","protocol":1,"entry":"<pre-commit\|pre-push\|ci>","settings":{...},"capabilities":[]}` | Handshake. `settings` is the YAML map under this check (excluding `run`, `timeout`, `sources`, `rules`), JSON-encoded with string keys. `capabilities` is always `[]` in protocol 1. |
| check → tool | `{"type":"ready","protocol":1,"rules":[{"id":"<check>/<rule>","summary":"...","defaultSeverity":"error\|warning"}]}` | Declares rules. `defaultSeverity` optional; default `error`. Every `id` must use this check's id as the first segment. |
| tool → check | `{"type":"run","changes":[{"path":"...","kind":"added\|modified\|deleted\|renamed","previousPath":null\|"..."}],"all":false}` | Starts the run. `all` is true when `--all` was passed. `previousPath` only for renames. |
| check → tool | `{"type":"read","id":<int>,"path":"...","side":"snapshot"\|"base"}` | Requests file text. `base` is the other side of the changeset; may be unanswered with `text: null`. |
| tool → check | `{"type":"content","id":<int>,"text":null\|"..."}` | Answer. `text` is null when the path is missing, unreadable, binary, or over the 5 MiB text limit (S6). |
| check → tool | `{"type":"finding","rule":"<check>/<rule>","path":"...","line":1,"column":1,"message":"..."}` | One finding. `line`/`column` are 1-based; both required. |
| check → tool | `{"type":"done"}` | Ends successfully. |

Order: exactly one `init` → one `ready` → one `run` → zero or more `read`/`content` pairs and zero or more `finding` → one `done`. After `done`, the host closes stdin and awaits exit. Findings may appear before or after reads. A `read` for an unknown `id` correlation is a protocol error.

### 10.2 What crosses the boundary (protocol 1)

| Served | Not served |
|---|---|
| Snapshot (and base) file **text** via `read` | `DartFileFacts`, ASTs, import graph objects |
| Change list with rename `previousPath` | Working-tree bytes |
| Entry kind, settings map, `all` flag | Fixes, autofix APIs |

Authors who need facts parse text themselves (or call their own tooling). A later protocol version may add capabilities; negotiation is the `capabilities` array (empty in v1).

### 10.3 Findings and the changeset

A finding whose `path` is inside the repository (valid `RepoPath`) is **accepted even when that path is not in the changeset**. The host still applies `exclude`, rule levels, `stagelatch:ignore`, and the baseline. Authors should normally restrict work to `changes` unless they intentionally scan further (for example under `--all`).

## 11. Adversarial child I/O

Stdout and stderr of the child are untrusted (S5, S6, S14).

| Limit | Value | On breach |
|---|---|---|
| Max stdout line length | 1 MiB | Protocol error; exit 70 |
| Max findings per check per run | 10_000 | Protocol error after the limit; exit 70 |
| Max stderr retained | first 64 KiB | Remainder dropped |
| Path with `..`, absolute, or outside the repo | — | Protocol error; exit 70 |
| Finding rule not declared in `ready` | — | Protocol error; exit 70 |
| Finding rule whose check segment ≠ this check id | — | Protocol error; exit 70 |
| Non-JSON or unknown `type` on stdout | — | Protocol error; exit 70; message includes the offending line truncated to 200 characters after S5 sanitization |
| Child exits non-zero before `done` | — | Exit 70: `custom check "<id>": exited with code <n>.` (stderr excerpt if any) |
| Child exits 0 without `done` | — | Exit 70: `custom check "<id>": exited before done.` |
| Extra stdout after `done` | — | Ignored |

Protocol error message shape:

```
custom check "<id>": protocol error: <reason>
```

Any protocol error, crash, start failure or timeout is an **internal error** (exit 70) naming the check. Source divergence is a **usage error** (exit 64) per §6. Neither is turned into a silent pass or a mere warning.

## 12. Integration with ignore, baseline and reporters

- Declared rules participate in `stagelatch:ignore`, root `rules:`, `exclude`, baseline fingerprints, and all reporters exactly like built-in rules once the handshake has succeeded.
- `stagelatch/invalid-ignore` and custom ids:
  - **Check active** (child ran or will run): an ignore naming `team/no-print` is valid if that rule was declared in a `ready` of this run **or** is listed under `custom_checks.team.rules` / selectors (so editors can ignore before the child runs). A rule id whose check segment is this custom id but that was **not** declared in the handshake yields `stagelatch/invalid-ignore` as usual.
  - **With `--no-custom-checks`:** a `stagelatch:ignore` whose `<check>` prefix is the id of a **configured** custom check (present under `custom_checks:`) is accepted without verifying the rule id against a handshake. A prefix that is neither a built-in check nor a configured custom check still yields `stagelatch/invalid-ignore`.
- `baseline create` / `prune` run with custom checks enabled (unless the user passes `--no-custom-checks` to the underlying pipeline — baseline commands do not expose that flag in 1.0.0; they run custom checks). Fingerprints use the same algorithm. When custom checks are configured, `baseline create` **executes project code** (same class of warning as `ci` / `tests/affected`).
- JSON reporter: custom findings appear in `findings` with their rule ids; check timings include the custom check id. `schemaVersion` stays `1`.
- SARIF: one rule descriptor per declared custom rule (id + summary). JUnit: one `testcase` per custom check id that ran.
- `doctor`: lists each custom check id, the resolved command, inferred or configured sources, and whether the executable is resolvable (probe; does not speak the protocol).

## 13. `--no-custom-checks`

Accepted by `run` and `ci`. When set:

- No custom-check process is started.
- Hook selectors that name only custom checks are skipped.
- Notice on stderr (console) or in the JSON `notices` list: `Skipping custom checks (--no-custom-checks).`
- Documented for pull requests from forks: CI that runs untrusted code should pass the flag or use the project's usual fork restrictions (S8, S14).

## 14. Author kit (1.0.0)

- Guide: `docs/custom-checks.md` (user-facing walkthrough).
- Reference: `example/custom_check/` — a minimal Dart program that speaks protocol 1, plus a README.
- No published `stagelatch_core` package in 1.0.0.

## 15. Latency (measurement)

On macOS 15 (Darwin 27.2), Apple silicon, Dart 3.13.4, a minimal protocol peer via `dart run`:

| | Wall time |
|---|---|
| Cold | **0.66 s** |
| Warm (subsequent) | **0.44–0.54 s** |

stagelatch itself already spends ~0.8 s of JIT startup (ADR-0004). A default `pre-commit` custom check would consume most or all of the 1–2 s pre-commit budget before any real work. Therefore custom checks are **not** on the default `pre-commit` list; they default with other heavy work to `pre-push` and `ci` (S14 amendment). Teams may still opt in on `pre-commit` knowingly.

## 16. Exact exit mapping

| Situation | Exit |
|---|---|
| Findings with severity `error` after filters | 1 |
| Source closure diverges | 64 |
| Protocol / timeout / crash / start failure | 70 |
| Bad `custom_checks` config (incl. empty / uninferable `sources`) | 78 |
| `--no-custom-checks` and no other problems | 0 |

## 17. Design questions (closed by this proposal)

Owner-approved resolutions (plan 05 Task 1):

1. No `stagelatch_core` in 1.0.0 — protocol + `example/` + guide.
2. Protocol 1 serves text via `read` only — no facts.
3. One process per check invocation — no keep-alive.
4. Default timeout 60s; kill + exit 70; key `custom_checks.<id>.timeout`.
5. Working tree + ADR-0018-style source closure; diverge → **exit 64** (usage), with entry-point-specific resolve hints and `--no-custom-checks`.
6. Default entry points: pre-push and ci; pre-commit opt-in only; `baseline create` / `prune` run custom checks.
7. `run` list; `dart`/`flutter` → resolved SDK; else explicit PATH walk (skip `.` / relative / in-repo dirs), absolute path to `Process.start`; Windows `.bat` guard; planted root executable must not run (AC-36).
8. Timeout ≠ `time_budget`.
9. Lifetime as (3); concurrent with other verify checks.
10. Boundary as §10.2; `protocol: 1`; empty `capabilities`.
11. Deferred rule validation; ignore/baseline/SARIF/JSON as §12 (including `--no-custom-checks` accepting ignores whose check prefix is a configured custom id).
12. Adversarial limits as §11.
13. No separate package release mechanics in 1.0.0.
14. Stability list in [`docs/stability.md`](../stability.md) (config keys/types/defaults/rejects/exit 78 frozen; validation message text not; hook marker + invocation contract frozen, not script bytes).
15. Public Dart API remains `packageVersion` only (ADR-0004).

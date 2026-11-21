# ADR-0019: Custom checks run out of process over a JSON protocol

- Status: Proposed
- Date: 2026-11-21

## Context

Teams need project-specific rules with the same reporting, suppression and baseline behaviour as built-ins. ADR-0004 forbids shipping stagelatch as a `dev_dependency`, so the tool cannot `import` project code and the project cannot import the tool without reintroducing version conflicts. The draft in `docs/specs/custom-checks.md` sketched an out-of-process protocol; plan 05 cannot start until that design is re-approved.

`tests/affected` (ADR-0018, S14) already starts project code on `pre-push` and `ci`, with a divergence guard and Windows `.bat` rules. Custom checks are a second, broader exception: the executable is named by config (today S1 forbids that), and the child speaks a host-defined protocol rather than `dart test`.

Measurements on this machine (macOS arm64, Dart 3.13.4): a minimal protocol peer via `dart run` takes **0.66 s cold** and **0.44–0.54 s warm**, before any check work. Together with the tool's own ~0.8 s JIT startup (ADR-0004), a default `pre-commit` custom check would exhaust the 1–2 s pre-commit budget.

## Decision

1. **Out-of-process protocol.** A custom check is a child process speaking line-delimited JSON on stdin/stdout (`protocol: 1`), specified in [`custom-checks.md`](../specs/custom-checks.md). Verify-phase only; no fixes in 1.0.0.
2. **S1 exception.** `custom_checks.<id>.run` may name an executable as a non-empty argument list. Still never a shell. If `run[0]` is `dart` or `flutter`, the host substitutes the resolved project SDK binary; otherwise PATH / path resolution as in the spec. Windows `.bat` / `.cmd` arguments follow the S14 metacharacter guard.
3. **S14 amendment.** Custom checks may start project (or PATH) code on `pre-push` and `ci` when selected by hook lists. They are not on the default `pre-commit` list. `doctor`, `why`, `init`, `install`, `uninstall` and `baseline` never start a custom-check process (`baseline` runs the pipeline with custom checks enabled but is not itself a starter outside the pipeline). `--no-custom-checks` disables them for fork-safe CI.
4. **Source divergence.** Program bytes come from the working tree; analyzed content comes only through protocol `read` (snapshot). Before start and after exit, the host applies an ADR-0018-style divergence test on the check's source closure. On diverge: do not trust results; **exit 70** naming the check (stricter than `tests/affected`'s warning skip, because skipping an opted-in gate would silently weaken it).
5. **Timeout.** Default `60s` per check (`custom_checks.<id>.timeout`). On exceed: kill child, exit 70. This is not `time_budget` (ADR-0003 still only warns).
6. **Lifetime.** One process per pipeline invocation of that check; no keep-alive across pre-push refs.
7. **Boundary for protocol 1.** Text via `read` only. No `DartFileFacts`, no import graph over the wire. Empty `capabilities` array reserved for later negotiation.
8. **No `stagelatch_core` in 1.0.0.** Protocol docs, `docs/custom-checks.md` author guide, and `example/custom_check/`. Revisit a helper package after 1.0.0 if needed.
9. **Public Dart API.** `lib/stagelatch.dart` continues to export only `packageVersion` (ADR-0004). The stability contract lives in [`docs/stability.md`](../stability.md).

## Consequences

- Security checklist and S1/S14 text must name this exception and the divergence/timeout/kill rules.
- Config loader accepts `custom_checks` from 1.0.0; rule id validation for custom rules is deferred until handshake.
- Acceptance scenarios AC-29+ cover protocol abuse, timeout, divergence, `--no-custom-checks`, and Windows `.bat` args.
- Pushing a branch that is not checked out typically fails (exit 70) when custom checks are selected; authors check out that branch or rely on `ci`.
- A separate pub package would add a second versioning/release track without removing the need to document the protocol; deferred.

## Alternatives rejected

- **In-process plugins / `dev_dependency`.** Conflicts with ADR-0004.
- **Separate `stagelatch_core` in 1.0.0.** Double release surface; protocol + example is enough to ship. CLAUDE.md already said to evaluate at 1.0.0 — evaluation result: not yet.
- **Serve `DartFileFacts` in protocol 1.** Couples the public protocol to an evolving internal schema (ADR-0013/0017); authors can parse text. Revisit via `capabilities` later.
- **Keep-alive across pre-push refs.** Shared mutable state, harder cleanup, little gain vs one-shot ~0.5 s spawn when the check itself dominates.
- **Materialize check sources and run from the snapshot directory.** Needs package configs / assets for non-trivial checks; high cost. Divergence guard is the cheaper ADR-0018 lesson.
- **Warning-skip on diverge (copy ADR-0018 exactly).** Would allow a green push while the custom gate did not run. Rejected for opted-in gates; owner may still choose this — flagged in the Task 1 PR.
- **Default custom checks on `pre-commit`.** Measurement: 0.5–0.7 s spawn alone plus tool startup breaks the 1–2 s budget.
- **Timeout as part of `time_budget`.** Would either skip (forbidden by ADR-0003) or conflate hang-kill with a soft advisory.
- **Public Dart check API in `lib/stagelatch.dart`.** Would pull host projects toward depending on the tool; contradicts ADR-0004. Protocol is the API.

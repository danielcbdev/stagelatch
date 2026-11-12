# ADR-0005: One engine for hooks and CI

- Status: Accepted
- Date: 2026-11-11

## Context

Hooks are optional by nature: `--no-verify`, a missing install, or an agent that skips them. A gate that exists only locally guarantees nothing. A separate CI implementation would drift from the local one.

## Decision

- `stagelatch run <hook>` and `stagelatch ci` call the same `Pipeline` with a different `EntryPoint`. There is no CI-only or hook-only check logic.
- The local hook is fast feedback. The guarantee is `stagelatch ci` on the pull request.
- Differences between entry points are limited to: which snapshot and changeset (ADR-0007), which selectors (`hooks.<name>`), and that fixes are applied only to the index.

## Consequences

- A finding seen locally is the finding seen in CI, with the same rule ID and location.
- The engine cannot assume a TTY, a developer machine or a mutable index.
- Hooks may be lenient about a missing tool (ADR-0006) precisely because CI is strict.

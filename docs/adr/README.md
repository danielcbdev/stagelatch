# Architecture decision records

One file per decision, numbered, never renumbered. A decision is changed by a new ADR that supersedes the old one; the old file stays and its status becomes `Superseded by ADR-NNNN`.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-validate-the-index-not-the-working-tree.md) | Validate the index, not the working tree | Accepted |
| [0002](0002-safe-autofix-through-the-index.md) | Safe autofix through the index | Accepted |
| [0003](0003-deterministic-verdicts.md) | Deterministic verdicts, no AI, no network | Accepted |
| [0004](0004-global-activation-only.md) | Distribution by global activation only | Accepted |
| [0005](0005-one-engine-for-hooks-and-ci.md) | One engine for hooks and CI | Accepted |
| [0006](0006-thin-hook-scripts.md) | Thin hook scripts that never block when the tool is missing | Accepted |
| [0007](0007-snapshot-and-changeset-per-entry-point.md) | Snapshot and changeset per entry point | Accepted |
| [0008](0008-parity-with-the-project-sdk.md) | Parity with the project SDK | Accepted; mechanism pending the spike |
| [0009](0009-rule-ids-as-the-only-vocabulary.md) | Rule IDs as the only vocabulary | Accepted |
| [0010](0010-explicit-suppression.md) | Explicit, localized suppression | Accepted |
| [0011](0011-never-interactive-without-a-tty.md) | Never interactive without a TTY | Accepted |
| [0012](0012-ports-and-adapters.md) | Ports and adapters with five modules | Accepted |
| [0013](0013-checks-consume-facts-not-asts.md) | Checks consume facts, not ASTs | Accepted |
| [0014](0014-two-phase-pipeline.md) | Two-phase pipeline: fix, then verify | Accepted |
| [0015](0015-config-and-baseline-come-from-the-snapshot.md) | Config and baseline come from the snapshot | Accepted |
| [0016](0016-branching-and-release-flow.md) | Branching and release flow | Accepted |

ADRs 0001–0011 record decisions already fixed in `CLAUDE.md`. ADRs 0012–0016 were added with the implementation documentation and approved by the owner on 2026-11-12.

## Template

```markdown
# ADR-NNNN: Title

- Status: Proposed | Accepted | Superseded by ADR-NNNN
- Date: YYYY-MM-DD

## Context
The forces at play. What breaks if we do nothing.

## Decision
What we do, stated so that code can be checked against it.

## Consequences
What becomes easier, what becomes harder, what we must now test.

## Alternatives rejected
Each with the reason.
```

In code, cite an ADR where a reader would otherwise wonder why: `// ADR-0007: during a merge only paths that differ from both parents count.`

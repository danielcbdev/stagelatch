# ADR-0014: Two-phase pipeline: fix, then verify

- Status: Accepted
- Date: 2026-11-11

## Context

When `format` rewrites a file in the index, line and column numbers move. If `analyze` ran on the pre-fix text, its locations would point at lines that no longer exist in the commit, and inline `stagelatch:ignore` comments could be matched against the wrong lines.

## Decision

- Each check declares `CheckPhase.fix` or `CheckPhase.verify`.
- The pipeline runs all fix-phase checks first, applies their fixes to the index when allowed (ADR-0002), then reopens the snapshot.
- Verify-phase checks run afterwards, concurrently, against the post-fix snapshot.
- When fixes cannot be applied (commit snapshot, or `fix: false`), fix-phase checks simply contribute findings and both phases see the same snapshot.
- `format` is the only fix-phase check in the current scope.

## Consequences

- Every reported location refers to the content that will actually be committed.
- A fix-phase check's findings for files it fixed are converted to `AppliedFix` records and do not block.
- Fix-phase checks run sequentially in registry order, so two fixers can never race on one file.

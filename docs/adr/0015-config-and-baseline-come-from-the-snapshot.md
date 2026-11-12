# ADR-0015: Config and baseline come from the snapshot

- Status: Accepted
- Date: 2026-11-11

## Context

ADR-0001 says the verdict concerns the snapshot. If `stagelatch.yaml` or the baseline were read from the working tree, an unstaged edit to either would change the local verdict while CI, which sees the committed files, decides differently.

## Decision

- `stagelatch.yaml` and the baseline file are read from the snapshot being judged.
- When `stagelatch.yaml` is absent from the snapshot but present in the working tree, the working tree copy is used and the report carries the notice `stagelatch.yaml is not staged; using the working tree copy`.
- When it is absent everywhere, built-in defaults apply.
- `baseline create` and `baseline prune` write the baseline to the working tree; the developer stages it like any other file.

## Consequences

- A pull request that weakens the config is judged by its own, weaker config. That change is visible in the diff and is a review concern, documented in [`security.md`](../engineering/security.md).
- `ConfigLoader` takes a `SnapshotFiles`, not a file path.
- Acceptance scenario: stage a config change that turns a rule off, keep an unstaged one that turns it on, and assert the staged one wins.

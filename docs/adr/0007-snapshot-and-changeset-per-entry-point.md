# ADR-0007: Snapshot and changeset per entry point

- Status: Accepted
- Date: 2026-11-11

## Context

"Validate the index" is only true for pre-commit. A push publishes commits; a pull request publishes a branch head. Each entry point needs a precise definition of what is judged (the snapshot) and what counts as changed (the changeset).

## Decision

| Entry | Snapshot | Changeset |
|---|---|---|
| pre-commit | index | index vs `HEAD`; on an unborn branch, vs the empty tree |
| pre-push | each pushed commit, read from the hook's stdin | base..pushed commit |
| `ci` | head of the pull request | `merge-base(base, head)`..head |

- **Pre-push base.** When the remote already has the branch, the base is the remote sha. For a new branch (remote sha all zeros), the base is the newest commit of the pushed history that some branch of that remote already contains: `git merge-base <local sha> <every refs/remotes/<remote>/*>`. With no such commit, the base is the empty tree.
- **Branch deletion** (local sha all zeros) and **tag pushes** have nothing to validate.
- **Merge in progress** (`MERGE_HEAD` exists): the changeset is the set of paths that differ from **every** parent, i.e. conflict resolutions and manual edits. Paths taken unchanged from either side were already validated on their own branch.
- **Rebase in progress:** when the hook fires, the normal changeset applies.
- **Shallow clone in CI** with no reachable merge base: usage error asking for `fetch-depth: 0`. A wrong diff is never analyzed.
- Overlays follow ADR-0001 for every snapshot kind.

## Consequences

- `GitRepository.resolve` returns a list of runs; pre-push may contain several.
- Acceptance tests cover each row and each special case above.

## Refinement of CLAUDE.md

`CLAUDE.md` originally said the base of a new pushed branch was "the merge-base with the remote's default branch". This ADR uses the merge-base with all branches of that remote, which is correct for branches cut from `develop` or from another feature branch. Approved on 2026-11-12 as refinement R1 in [`specs/README.md`](../specs/README.md#refinements-to-claudemd); `CLAUDE.md` now states the same rule.

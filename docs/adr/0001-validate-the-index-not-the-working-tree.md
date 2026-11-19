# ADR-0001: Validate the index, not the working tree

- Status: Accepted
- Date: 2026-11-11

## Context

A commit contains the index, not the working tree. Tools that run `dart analyze` on disk judge files the commit does not contain: with `git add -p`, an unstaged half of a file can hide an error in the staged half, or report one that is not being committed. The usual workaround, `git stash`, rewrites the working tree under the developer and can lose work when it fails midway.

## Decision

- Every check reads file content from the snapshot being published. For pre-commit that is the index.
- Blobs are read through one persistent `git cat-file --batch` process: one spawn per run, not one per file.
- Dart analysis sees the snapshot through content overlays. The overlay holds the snapshot version of **every** file that differs between the snapshot and the working tree (`git diff --name-only -z`), not only the staged ones, because an unstaged edit in a dependency changes the analysis of a staged file.
- `git stash` is never used.

## Consequences

- The verdict matches what will be committed, including under partial staging.
- No check may read the working tree. The architecture enforces this by giving checks only `SnapshotFiles`.
- Tools that cannot take overlays (anything that only reads disk) cannot be used directly.

## Alternatives rejected

- **Stash unstaged changes, run on disk, pop:** mutates user state; unsafe on failure; breaks editors and watchers.
- **Check out the index into a temp directory:** loses `.dart_tool/package_config.json` and relative path resolution, and costs a full copy on every commit.

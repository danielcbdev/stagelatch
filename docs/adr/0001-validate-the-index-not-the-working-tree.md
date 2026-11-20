# ADR-0001: Validate the index, not the working tree

- Status: Accepted
- Date: 2026-11-11; analysis mechanism amended 2026-11-19 (materialized snapshot instead of overlays)

## Context

A commit contains the index, not the working tree. Tools that run `dart analyze` on disk judge files the commit does not contain: with `git add -p`, an unstaged half of a file can hide an error in the staged half, or report one that is not being committed. The usual workaround, `git stash`, rewrites the working tree under the developer and can lose work when it fails midway.

## Decision

- Every check reads file content from the snapshot being published. For pre-commit that is the index.
- Blobs are read through one persistent `git cat-file --batch` process: one spawn per run, not one per file.
- Dart analysis sees the snapshot and nothing else. The snapshot's `.dart`, `.yaml` and `.yml` files are written from their blobs into a fresh temporary directory, with each package's `.dart_tool/package_config.json` copied in, and the resolved SDK's analysis server analyzes that directory ([`dart-toolchain.md`](../specs/dart-toolchain.md#4-diagnostics)). An unstaged edit, an untracked file and a file deleted only in the index are therefore all invisible to the verdict.
- `git stash` is never used.

## Consequences

- The verdict matches what will be committed, including under partial staging.
- No check may read the working tree. The architecture enforces this by giving checks only `SnapshotFiles`.
- Tools that only read disk can be used on the materialized directory, never on the working tree.
- Each analysis pays for writing the snapshot's Dart and YAML files: about 0.25 s for 2,472 files on the spike's corpus, against about 13 s for the analysis server itself.

## Alternatives rejected

- **Stash unstaged changes, run on disk, pop:** mutates user state; unsafe on failure; breaks editors and watchers.
- **Content overlays over the working tree** (the original decision, until 2026-11-19): show the analyzer the snapshot version of every file that differs from the working tree (`git diff --name-only -z`). Rejected after the spike: the analysis server, like `OverlayResourceProvider` over the physical file system, still reads every other file from disk, so an untracked file or a file deleted only in the index stays visible, and a commit that imports a file it does not contain passes. Excluding the path through `analysis.setAnalysisRoots` does not hide it from importers (measured).
- **A full checkout into a temp directory:** writes every file, assets included. Only Dart and YAML files matter to analysis, and the package config is copied with its in-repository roots kept relative, as the spike's oracle does.

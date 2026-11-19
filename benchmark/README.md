# stagelatch_bench

Throwaway spike for [plan 00](../docs/plans/00-spike.md): it measures two
ways of diagnosing and formatting a git snapshot of a large Flutter app,
and feeds [ADR-0008](../docs/adr/0008-parity-with-the-project-sdk.md).
Nothing in `lib/` of stagelatch imports it, and it is never published.

## Setup

Needs git, FVM and network access (setup only; the probes run offline).

```bash
fvm install 3.47.8
dart pub get --directory benchmark
dart run benchmark/bin/setup.dart
```

`setup.dart` clones the corpus named in [`corpus.yaml`](corpus.yaml) into
`.benchmark/corpus` (ignored by git), checks out the pinned SHA and runs
`flutter pub get --enforce-lockfile` with the pinned Flutter. A second run
is a no-op.

## Scenarios

`scenarios/<name>/` holds `staged.patch` (applied to the index),
`unstaged.patch` (applied to the working tree) and `expected.md` (the
resulting `git status` and the findings the snapshot must produce).
`applyScenario` in `lib/scenario.dart` resets the corpus before applying.

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

## The real CLI (plan 02, Task 17)

`bin/measure_cli.dart` times the activated `stagelatch` executable, from
process start to exit, on the same corpus and scenarios:

```bash
dart pub global activate --source path .
cd benchmark
dart run bin/measure_cli.dart                   # default analyze.scope: affected
dart run bin/measure_cli.dart --scope changed   # analyze only the changed files
```

- `run pre-commit --no-fix` with the default lists (format, pubspec,
  sensitive-files). `--no-fix` keeps the index identical across runs.
- `run pre-push` (analyze) over a commit of the staged scenario, git's input
  on stdin.
- 3 cold runs, with `HOME` pointed at a fresh temporary directory so the
  analysis server starts with an empty cache (your own cache is never
  touched); then 11 warm runs, the first discarded. Results go to
  `results/17-cli.json` and `results/17-cli-scope-changed.json`.

Measured on 2026-11-19 on an Apple M-series laptop, Flutter 3.47.8 (Dart
3.13.7) resolved through FVM, stagelatch at the commit of the 0.1.0 release:

| Hook | Scope | Scenario | Cold p50 / p95 | Warm p50 / p95 |
|---|---|---|---|---|
| pre-commit | n/a | s3 | 0.56 / 0.64 s | 0.78 / 0.89 s |
| pre-commit | n/a | s10 | 0.62 / 0.80 s | 0.92 / 1.05 s |
| pre-push | affected | s3 | 46.4 / 47.8 s | 31.5 / 32.2 s |
| pre-push | affected | s10 | 46.9 / 48.9 s | 32.7 / 33.8 s |
| pre-push | changed | s3 | 21.6 / 21.7 s | 11.8 / 12.9 s |
| pre-push | changed | s10 | 22.2 / 22.2 s | 12.1 / 13.0 s |

Read with the spike's numbers in mind ([`docs/spike/report.md`](../docs/spike/report.md)):

- The commit hook stays within the 1–2 s target: `analyze` is not on it by
  default (ADR-0008), and formatting pipes each file to the SDK's `dart
  format` in about 20 ms.
- `analyze` pays one analysis server start per run on the materialized
  snapshot. With `scope: changed` that is close to the spike's 13.6 s for
  the same server. The default `affected` scope also analyzes every file
  that imports a changed one, which on this app is hundreds of files.
- Cold pre-commit runs come out faster than warm ones. The cause was not
  investigated; a fresh `HOME` also changes the `dart` tool's own state
  (its settings and analytics files). Every pre-commit run stays under
  1.1 s at p95, cold or warm.

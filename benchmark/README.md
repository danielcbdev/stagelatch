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

## Pre-commit with the 0.2.0 checks (plan 03, Task 10)

The same two scenarios, with every default pre-commit check of 0.2.0 (format,
codegen, pubspec, l10n, assets, sensitive-files, tests/solo,
tests/new-skip) running on the corpus, which has no `stagelatch.yaml`:

```bash
dart pub global activate --source path .
cd benchmark
dart run bin/measure_cli.dart --hook pre-commit --cold 5 --warm 10 \
  --out 18-cli-0.2.0-pre-commit.json
```

Measured on 2026-11-20 on the same laptop and SDK as above. Results are in
`results/18-cli-0.2.0-pre-commit.json`; 0.1.0 is repeated for comparison.

| Version | Scenario | Cold p50 / p95 | Warm p50 / p95 |
|---|---|---|---|
| 0.2.0 | s3 | 0.55 / 0.56 s | 0.77 / 0.78 s |
| 0.2.0 | s10 | 0.61 / 0.63 s | 0.83 / 0.85 s |
| 0.1.0 | s3 | 0.56 / 0.64 s | 0.78 / 0.89 s |
| 0.1.0 | s10 | 0.62 / 0.80 s | 0.92 / 1.05 s |

The new checks add no measurable time to the commit hook on these scenarios.
A first run of the day, right after `dart pub global activate`, took 2.0 s
once; five more cold runs afterwards stayed at 0.55 s to 0.63 s, so that run
is treated as the warm-up of the activation and is not in the table.

## The fact extractor (plan 03, ADR-0017)

`bin/facts.dart` compares two ways of extracting annotated declarations,
test calls and identifiers: `lib/facts_scanner.dart` (a hand-written
lexer, the candidate that was chosen) and `lib/facts_parse.dart`
(`package:analyzer`, the reference). The measurements are in
[`docs/spike/facts-report.md`](../docs/spike/facts-report.md), which also
lists the commands to reproduce them (`compare`, `edges`, `fuzz`,
`adversarial`, `scan`, `parse`, `sha`). Nothing of stagelatch imports these
files.

## The facts cache (plan 04, Task 1)

`bin/cache.dart` times `CachedFacts.facts` over every `.dart` file of the
corpus at the pinned SHA: the extractor alone, an empty cache, a warm cache,
and the cold and warm runs again in fresh processes.

```bash
dart run benchmark/bin/cache.dart
```

Measured on 2026-11-21 on an Apple M-series laptop, 2,462 `.dart` files:

| Run | Time |
|---|---|
| extractor alone (no cache) | 636 ms |
| empty cache, same process (extract and store) | 1,290 ms |
| warm cache, same process | 218 ms |
| empty cache, fresh process | 1,541 ms |
| warm cache, fresh process | 264 ms |

## `l10n/unused-key` on the commit hook (plan 04, Task 2)

`l10n/unused-key` scans every non-generated `.dart` file of the package, so a
staged `.dart` file makes it look at the whole package. The corpus has an
`l10n.yaml` and a template of 4,156 keys, so `s3-l10n` and `s10-l10n` reuse the
patches of `s3` and `s10` unchanged. `measure_cli.dart` deletes the corpus's
facts cache (`.git/stagelatch/cache`) before each cold run, as well as using a
fresh `HOME`:

```bash
dart pub global activate --source path .
cd benchmark
dart run bin/measure_cli.dart --hook pre-commit --scenario s3-l10n \
  --scenario s10-l10n --cold 8 --warm 10 --out 19-cli-0.3.0-l10n-pre-commit.json
```

Measured on 2026-11-21 on the same laptop and SDK as above, with the default
pre-commit list of 0.3.0 (format, codegen, pubspec, l10n, assets,
sensitive-files, tests/solo, tests/new-skip). Cold: no facts cache and an empty
analysis cache; warm: both populated.

| Scenario | Cold p50 / p95 | Cold min-max | Warm p50 / p95 |
|---|---|---|---|
| s3-l10n | 1.79 / 1.88 s | 1.73-1.88 s | 1.20 / 1.29 s |
| s10-l10n | 1.83 / 1.85 s | 1.80-1.85 s | 1.26 / 1.43 s |
| 0.2.0 (no unused-key), s3 | 0.55 / 0.56 s | | 0.77 / 0.78 s |
| 0.2.0 (no unused-key), s10 | 0.61 / 0.63 s | | 0.83 / 0.85 s |

Both stay under the 2 s gate, with about 0.12 s of margin at the worst cold
run. In a first measurement taken right after `dart pub global activate`, the
very first cold run (s3) took 2.2 s, and the 9 cold runs after it stayed
between 1.73 and 1.94 s; as in the 0.2.0 table above, that run is the
activation warm-up. The table is a second, complete measurement (8 cold and
10 warm runs per scenario) in which no run exceeded 1.89 s. Compared with 0.2.0, the rule adds about 1.2 s cold (extracting the
identifiers of 2,462 files and storing them) and about 0.4 s warm (listing the
snapshot and reading 2,462 cache entries); these are differences of medians,
not a profile.

## Default hooks of 0.3.0 (plan 04, Task 10)

The default `pre-commit` list (including `l10n/unused-key` on this corpus,
which has an `l10n.yaml`) and the default `pre-push` list (`analyze` and
`tests/affected`) on `s3` and `s10`. Cold deletes the corpus facts cache and
uses a fresh `HOME`; warm keeps both caches. On these scenarios the unstaged
edit makes the affected-test closure diverge, so `tests/affected` reports the
skip warning and starts no test process; the pre-push time is essentially
`analyze` plus selection and the divergence check.

```bash
dart pub global activate --source path .
cd benchmark
dart run bin/measure_cli.dart --hook pre-commit --hook pre-push \
  --scenario s3 --scenario s10 --cold 3 --warm 10 --out 19-cli-0.3.0.json
```

Measured on 2026-11-21 on the same laptop and SDK. Results are in
`results/19-cli-0.3.0.json`.

| Hook | Scenario | Cold p50 / p95 | Warm p50 / p95 |
|---|---|---|---|
| pre-commit | s3 | 1.82 / 2.20 s | 1.26 / 1.31 s |
| pre-commit | s10 | 3.24 / 3.45 s | 1.59 / 1.65 s |
| pre-push | s3 | 38.7 / 40.7 s | 30.2 / 47.1 s |
| pre-push | s10 | 50.4 / 50.5 s | 30.9 / 31.4 s |

The first cold pre-commit run of the session (s3, 2.20 s) is the
activation warm-up, same disclosure as 0.2.0. Warm facts cache versus cold
cuts about 0.5 s (s3) to 1.6 s (s10) on the commit hook. Pre-push stays
near the analyze-only affected numbers of 0.1.0 because `tests/affected`
skips under the scenario's unstaged edit.

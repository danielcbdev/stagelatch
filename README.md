# stagelatch

Change-aware quality gate for Flutter and Dart repositories.

## The problem

A pre-commit hook that runs `dart format` and `dart analyze` on disk judges
the working tree, not the commit. With `git add -p`, an unstaged edit can
hide an error that is being committed, or report one that is not. Stashing
to work around it rewrites your working tree under you.

stagelatch judges exactly the snapshot being published: the index on
commit, the pushed commit on push, the pull request's head in CI. It reads
file content from git and runs the project's own SDK on a copy of that
snapshot, so its verdict is what `dart format` and `dart analyze` would say
about the commit itself. It only looks at what the change touches.

![A partially staged commit, formatted in the index, then blocked by a path dependency](docs/demo.gif)

## Quick start

```sh
dart pub global activate stagelatch
```

In a git repository with a `pubspec.yaml`, after `dart pub get`:

```sh
stagelatch init
```

`init` writes `stagelatch.yaml` and installs the `pre-commit` and
`pre-push` hooks. From then on:

- `git commit` formats the staged Dart files in the index (unstaged edits
  are left alone) and blocks on pubspec and sensitive-file problems;
- `git push` runs your SDK's `dart analyze` on what is being pushed, and
  runs the tests that the change affects when the working tree matches the
  pushed commit for those files.

`stagelatch doctor` explains what is installed and what is missing.

## What it checks

| Rule | Default hook | Blocks when |
|---|---|---|
| `format/unformatted` | pre-commit | a changed Dart file is not formatted; fixed in the index on commit |
| `analyze/<code>` | pre-push, ci | the SDK reports a diagnostic in a changed file or in one that imports it |
| `pubspec/path-dependency` | pre-commit | a `path` dependency leaves the repository |
| `pubspec/dependency-overrides` | pre-commit | `dependency_overrides` or `pubspec_overrides.yaml` is committed |
| `pubspec/unpinned-git` | pre-commit | a git dependency is not pinned to a ref (with `require_sha`, to a commit SHA) |
| `pubspec/build-number-regression` | pre-commit | the build number is lower than the base's, on the branches you list |
| `pubspec/lockfile-out-of-sync` | pre-commit | `pubspec.lock` does not satisfy the constraints of `pubspec.yaml` |
| `pubspec/unparseable` | pre-commit | a `pubspec.yaml` is not a YAML map |
| `codegen/stale` | pre-commit | a generated file (`.g.dart`, `.freezed.dart`) was not updated with its source |
| `l10n/missing-key` | pre-commit | a message of the template is missing in a translation |
| `l10n/placeholder-mismatch` | pre-commit | a translation's placeholders differ from the template's |
| `l10n/unused-key` | pre-commit | a key of the template is unused in any Dart file (warning) |
| `l10n/unparseable` | pre-commit | an ARB file is not a valid JSON object |
| `assets/missing` | pre-commit | a declared asset does not exist |
| `assets/undeclared` | pre-commit | a file under an asset root is not declared in `pubspec.yaml` |
| `assets/max-file-size` | pre-commit | an asset is larger than `assets.max_file_size` |
| `sensitive-files/signing` | pre-commit | a keystore, `.p8`, `.p12` or `key.properties` is committed |
| `sensitive-files/credentials` | pre-commit | an `.env` file or a service account key is committed |
| `tests/solo` | pre-commit | a test uses `solo`, which skips every other test |
| `tests/new-skip` | pre-commit | a test is skipped in this change (warning; old skips are never reported) |
| `tests/affected` | pre-push, ci | a test affected by the change fails, or cannot be run |
| `stagelatch/invalid-ignore` | every hook | a `stagelatch:ignore` names an unknown rule (warning) |

Every rule, with its default severity, is in the
[rule reference](https://github.com/danielcbdev/stagelatch/blob/main/docs/rules.md).
The SDK is the one your project uses: `sdk_path` in `stagelatch.yaml`, then
FVM (`.fvmrc`, `.fvm/flutter_sdk`), then `dart` on `PATH`.

### `tests/affected`

On push and in CI, stagelatch selects the test files the change touches and
the test files that import a changed or deleted file, directly or through
other files. It runs them with your package's `dart test` or `flutter test`.
It never runs on commit: a commit hook that started the suite would be too
slow, and the guarantee is `stagelatch ci` on the pull request.

Before the first process starts, and again after the last one, it checks that
the working tree matches the snapshot for the **closure**: those test files,
every Dart file they import (through `import`, `export` and `part`, including
conditional imports), and for each package that owns a selected test its
`pubspec.yaml`, `analysis_options.yaml`, and `pubspec.lock` when that lock
exists in the snapshot. If anything in that closure differs — an unstaged
edit, an untracked non-ignored file a test imports, or a push of a branch that
is not checked out — the suite is skipped with a warning and the push is
allowed. A green run means those files matched; it does not cover everything a
test process can read.

**Documented limitations (ADR-0018).** Selection ignores fixtures, goldens,
assets, `dart_test.yaml`, `flutter_test_config.dart`, `pubspec_overrides.yaml`,
`build.yaml`, and other config or data files that no `import`, `export` or
`part` reaches, and gitignored files. Divergence of those alone does not skip.
Generated Dart files when `codegen.generated_files_committed` is `false`, and
a gitignored `pubspec.lock`, are outside the guarantee the same way.

**Fork pull requests.** `stagelatch ci` with `tests/affected` executes the
pull request's tests and the code they import, like a `dart test` step. For
pull requests from forks the usual restrictions on secrets apply, and
workflows must use `pull_request`, never `pull_request_target`.

### `why`, workspaces and the facts cache

`stagelatch why <test-file>` prints why `tests/affected` would select that
test for the current changes, without starting a test process:

```
test/checkout/cart_test.dart is affected by 1 changed file:

lib/checkout/cart.dart (changed)
  imported by lib/checkout/cart_controller.dart
  imported by test/checkout/cart_test.dart
```

Pub workspaces are supported: members share the workspace root's
`pubspec.lock` and package config, and a lock change widens selection to every
member's tests.

Syntactic facts (directives, annotated declarations, test calls, identifiers)
are cached under `<git common dir>/stagelatch/cache` — that is
`.git/stagelatch/cache` in a plain clone. Linked worktrees share it. It is
safe to delete at any time; there is no eviction. A miss recomputes silently.

## Configuration

`stagelatch init` writes only the checks that fit your project: `codegen`
when `build_runner` is a dev dependency, `l10n` when there is an `l10n.yaml`,
`assets` when a pubspec declares assets. The file starts with a
`yaml-language-server` comment, so editors complete and validate its keys
from [`schema/stagelatch.schema.json`](schema/stagelatch.schema.json).

```yaml
min_version: 0.3.0

hooks:
  pre-commit: [format, codegen, pubspec, l10n, assets, sensitive-files, tests/solo, tests/new-skip]
  pre-push: [analyze, tests/affected]
  # ci: defaults to the union of the two lists above.

rules:
  l10n/unused-key: warning
  tests/new-skip: off              # error | warning | off

exclude: [lib/generated/**]

format:
  fix: true

analyze:
  scope: affected                  # changed | affected | all
  fail_on: [error, warning]

pubspec:
  monotonic_build_number: [release/*]

assets:
  max_file_size: 500KB
  ignore: [assets/videos/**]

baseline: .stagelatch/baseline.json
```

A finding can be silenced where it is, with its rule id:
`// stagelatch:ignore analyze/unused_import` in Dart or
`# stagelatch:ignore pubspec/dependency-overrides` in YAML, on the line or
the line before. The full reference is
[`docs/specs/config.md`](docs/specs/config.md).

## Adopting it in an existing project

A legacy codebase has findings you cannot fix today. `run` and `ci` take
`--all` to judge every file of the snapshot, not only the changed ones, and
a baseline records what is already there so that only new findings block:

```sh
stagelatch run pre-commit --all    # see everything the checks would report
stagelatch baseline create         # record today's findings
git add .stagelatch/baseline.json  # the baseline counts once it is staged
git commit -m "chore: adopt stagelatch"
```

An entry is the rule, the file and a fingerprint of the offending code, so
inserting lines above a finding keeps it accepted, while editing the code or
renaming the file brings it back. When you fix findings, `stagelatch
baseline prune` drops the entries that no longer match; it never adds
entries. `baseline create` refuses to overwrite a file; pass `--force` to
start over.

## CI

The hooks are fast feedback; the guarantee is the same engine on the pull
request:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0          # stagelatch ci needs the merge base
- uses: dart-lang/setup-dart@v1
- run: dart pub get
- uses: danielcbdev/stagelatch@v0.3.0
  with:
    base: origin/${{ github.base_ref }}
```

Findings appear as annotations on the pull request. `stagelatch ci
--reporter json` gives scripts and AI agents the same result as JSON.
`--reporter junit` prints JUnit XML on stdout. For code scanning, write
SARIF to a file with the action's `output` input and upload it (third-party
actions pinned to a full commit SHA per S8):

```yaml
- uses: danielcbdev/stagelatch@v0.3.0
  with:
    base: origin/${{ github.base_ref }}
    reporter: sarif
    output: stagelatch.sarif
- uses: github/codeql-action/upload-sarif@2d92b76c45b91eb80fc44c74ce3fce0ee94e8f9d # v3.30.0
  with:
    sarif_file: stagelatch.sarif
```

## Benchmark

Measured on a public Flutter app of 2,435 Dart files
([Hash-Studios/Prism](https://github.com/Hash-Studios/Prism) at a pinned
commit, Flutter 3.47.8), with the executable that `dart pub global
activate` installs, on a laptop. s3 stages 3 files and s10 stages 10, each
with an unstaged edit on top. Warm is p50 of 10 runs. Cold deletes the
corpus facts cache (`.git/stagelatch/cache`) and uses an empty analysis
cache.

| Hook | What runs | s3 warm | s10 warm |
|---|---|---|---|
| `pre-commit` | every default check of 0.3.0 (includes `l10n/unused-key` on this corpus) | 1.26 s | 1.59 s |
| `pre-commit` | 0.2.0, for comparison (no `unused-key`) | 0.77 s | 0.83 s |
| `pre-push` | analyze + `tests/affected` (default; suite skipped here by divergence) | 30.2 s | 30.9 s |
| `pre-push` | analyze, `scope: changed` (0.1.0) | 11.8 s | 12.1 s |
| `pre-push` | analyze, `scope: affected` (0.1.0 / 0.2.0) | 31.5 s | 32.7 s |

Cold (empty facts cache and empty analysis cache): pre-commit 1.82 s /
3.24 s; pre-push 38.7 s / 50.4 s. A warm facts cache saves about 0.6 s on
the dedicated `l10n/unused-key` runs (Task 2) and about 0.5–1.6 s on the
default commit hook versus cold.

`l10n/unused-key` alone on a package with 4,156 keys (Task 2, scenarios
`s3-l10n` / `s10-l10n`): cold 1.79 s / 1.83 s, warm 1.20 s / 1.26 s — under
the 2 s commit-hook gate.

On these `s3`/`s10` scenarios the unstaged edit makes the
`tests/affected` closure diverge, so the rule warns and starts no test
process; pre-push time stays in the same band as analyze-only affected.
`analyze` starts your SDK's analysis server once per run on a copy of the
snapshot, which on a large Flutter app costs seconds to tens of seconds, so
it runs on push and in CI by default. Cold runs, the method and the exact
commands are in [`benchmark/README.md`](benchmark/README.md):

```sh
dart pub global activate --source path .
cd benchmark && dart run bin/measure_cli.dart --hook pre-commit
```

## Limitations

- Analyzer plugins and `custom_lint` are not guaranteed to run.
- Hooks are advisory: anyone can `git commit --no-verify`, and a machine
  without stagelatch skips them. Run `stagelatch ci` on pull requests.
- `analyze` starts your SDK's analysis server once per run: about a second
  on a small Dart package, much longer on a large Flutter app (see the
  benchmark). That is why it runs on push and in CI by default.
- `tests/affected` runs on the working tree under the divergence rules
  above; see ADR-0018 for the documented limitations.
- No network access, no telemetry, no AI in the blocking path.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Passed. |
| 1 | Blocking findings. |
| 64 | Incorrect usage. |
| 70 | Internal error. |
| 78 | Invalid configuration. |

## License

[MIT](LICENSE)

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
- `git push` runs your SDK's `dart analyze` on what is being pushed.

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
| `l10n/unparseable` | pre-commit | an ARB file is not a valid JSON object |
| `assets/missing` | pre-commit | a declared asset does not exist |
| `assets/undeclared` | pre-commit | a file under an asset root is not declared in `pubspec.yaml` |
| `assets/max-file-size` | pre-commit | an asset is larger than `assets.max_file_size` |
| `sensitive-files/signing` | pre-commit | a keystore, `.p8`, `.p12` or `key.properties` is committed |
| `sensitive-files/credentials` | pre-commit | an `.env` file or a service account key is committed |
| `tests/solo` | pre-commit | a test uses `solo`, which skips every other test |
| `tests/new-skip` | pre-commit | a test is skipped in this change (warning; old skips are never reported) |
| `stagelatch/invalid-ignore` | every hook | a `stagelatch:ignore` names an unknown rule (warning) |

Every rule, with its default severity, is in the
[rule reference](https://github.com/danielcbdev/stagelatch/blob/main/docs/rules.md).
The SDK is the one your project uses: `sdk_path` in `stagelatch.yaml`, then
FVM (`.fvmrc`, `.fvm/flutter_sdk`), then `dart` on `PATH`.

## Configuration

`stagelatch init` writes only the checks that fit your project: `codegen`
when `build_runner` is a dev dependency, `l10n` when there is an `l10n.yaml`,
`assets` when a pubspec declares assets. The file starts with a
`yaml-language-server` comment, so editors complete and validate its keys
from [`schema/stagelatch.schema.json`](schema/stagelatch.schema.json).

```yaml
min_version: 0.2.0

hooks:
  pre-commit: [format, codegen, pubspec, l10n, assets, sensitive-files, tests/solo, tests/new-skip]
  pre-push: [analyze]
  # ci: defaults to the union of the two lists above.

rules:
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
- uses: danielcbdev/stagelatch@v0.2.0
  with:
    base: origin/${{ github.base_ref }}
```

Findings appear as annotations on the pull request. `stagelatch ci
--reporter json` gives scripts and AI agents the same result as JSON.

## Benchmark

Measured on a public Flutter app of 2,435 Dart files
([Hash-Studios/Prism](https://github.com/Hash-Studios/Prism) at a pinned
commit, Flutter 3.47.8), with the executable that `dart pub global
activate` installs, on a laptop. s3 stages 3 files and s10 stages 10, each
with an unstaged edit on top. Warm is p50 of 10 runs.

| Hook | What runs | s3 warm | s10 warm |
|---|---|---|---|
| `pre-commit` | every default check of 0.2.0 | 0.77 s | 0.83 s |
| `pre-commit` | 0.1.0, for comparison: format, pubspec, sensitive-files | 0.78 s | 0.92 s |
| `pre-push` | analyze, `scope: changed` | 11.8 s | 12.1 s |
| `pre-push` | analyze, `scope: affected` (default) | 31.5 s | 32.7 s |

Cold, with an empty analysis cache, the 0.2.0 commit hook takes 0.55 s (s3)
and 0.61 s (s10); 0.1.0 took 0.56 s and 0.62 s.

The commit hook stays under a second with the new checks. `analyze` starts your SDK's analysis
server once per run on a copy of the snapshot, which on a large Flutter app
costs seconds to tens of seconds, so it runs on push and in CI by default.
Cold runs, the method and the exact commands are in
[`benchmark/README.md`](benchmark/README.md):

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

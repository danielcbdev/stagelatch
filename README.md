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

## What 0.1.0 checks

| Rule | Default hook | Blocks when |
|---|---|---|
| `format/unformatted` | pre-commit | a changed Dart file is not formatted; fixed in the index on commit |
| `analyze/<code>` | pre-push, ci | the SDK reports a diagnostic in a changed file or in one that imports it |
| `pubspec/path-dependency` | pre-commit | a `path` dependency leaves the repository |
| `pubspec/dependency-overrides` | pre-commit | `dependency_overrides` or `pubspec_overrides.yaml` is committed |
| `pubspec/unparseable` | pre-commit | a `pubspec.yaml` is not a YAML map |
| `sensitive-files/signing` | pre-commit | a keystore, `.p8`, `.p12` or `key.properties` is committed |
| `sensitive-files/credentials` | pre-commit | an `.env` file or a service account key is committed |
| `stagelatch/invalid-ignore` | every hook | a `stagelatch:ignore` names an unknown rule (warning) |

The SDK is the one your project uses: `sdk_path` in `stagelatch.yaml`, then
FVM (`.fvmrc`, `.fvm/flutter_sdk`), then `dart` on `PATH`.

## Configuration

```yaml
min_version: 0.1.0

hooks:
  pre-commit: [format, pubspec, sensitive-files]
  pre-push: [analyze]
  # ci: defaults to the union of the two lists above.

rules:
  stagelatch/invalid-ignore: off   # error | warning | off

exclude: [lib/generated/**]

format:
  fix: true

analyze:
  scope: affected        # changed | affected | all
  fail_on: [error, warning]
```

A finding can be silenced where it is, with its rule id:
`// stagelatch:ignore analyze/unused_import` in Dart or
`# stagelatch:ignore pubspec/dependency-overrides` in YAML, on the line or
the line before. The full reference is
[`docs/specs/config.md`](docs/specs/config.md).

## CI

The hooks are fast feedback; the guarantee is the same engine on the pull
request:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0          # stagelatch ci needs the merge base
- uses: dart-lang/setup-dart@v1
- run: dart pub get
- uses: danielcbdev/stagelatch@v0.1.0
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
| `pre-commit` | format, pubspec, sensitive-files | 0.78 s | 0.92 s |
| `pre-push` | analyze, `scope: changed` | 11.8 s | 12.1 s |
| `pre-push` | analyze, `scope: affected` (default) | 31.5 s | 32.7 s |

The commit hook stays under a second. `analyze` starts your SDK's analysis
server once per run on a copy of the snapshot, which on a large Flutter app
costs seconds to tens of seconds, so it runs on push and in CI by default.
Cold runs, the method and the exact commands are in
[`benchmark/README.md`](benchmark/README.md):

```sh
dart pub global activate --source path .
cd benchmark && dart run bin/measure_cli.dart
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

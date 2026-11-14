# stagelatch

Change-aware quality gate for Flutter and Dart repositories.

stagelatch checks the git snapshot that is about to be published. In this
version that snapshot is the index, read by the pre-commit hook.

**Status: pre-release.** This is `0.1.0-dev.1`. It installs a pre-commit hook
and checks `pubspec.yaml`. Format, analyze, pre-push and `stagelatch ci` are
not in this version. There is no benchmark yet.

## Install

```sh
dart pub global activate stagelatch
```

`dart` must be on `PATH`. From a git repository:

```sh
stagelatch init
```

`init` detects the project, writes `stagelatch.yaml` and installs the
pre-commit hook. It does not prompt when stdout is not a terminal.

## What this version checks

On `pre-commit`, against the staged `pubspec.yaml`:

- `pubspec/path-dependency` blocks a `path` dependency whose target is
  outside this repository.
- `pubspec/dependency-overrides` blocks a `dependency_overrides` section.
- `pubspec/unparseable` blocks a `pubspec.yaml` that is not a YAML map.

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

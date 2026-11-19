# Configuration specification: `stagelatch.yaml`

Status: **Approved (2026-11-12).**

## 1. Location and loading

- The file is `stagelatch.yaml` at the repository root. There is one config per repository.
- It is read from the snapshot being judged (ADR-0015). Fallbacks: the working tree copy, with a notice; then built-in defaults.
- Every **key** of this document is parsed from the first version on, so a config written for a later version is not rejected for a parameter the running version does not act on.
- **Selectors and rule IDs** are different: a check or rule that the running version does not implement is rejected (exit 78). A rule is registered only by the version that implements it. This fails closed: an old tool never silently skips a check the team asked for. `min_version` is how a team states the version its config needs.

## 2. Full example

```yaml
min_version: 0.1.0

hooks:
  pre-commit: [format, analyze, codegen, pubspec, l10n, assets, sensitive-files, tests/solo, tests/new-skip]
  pre-push: [analyze, tests/affected]

rules:
  l10n/unused-key: warning
  tests/new-skip: warning
  pubspec/unpinned-git: off

exclude: [lib/generated/**]

# sdk_path: .fvm/flutter_sdk

time_budget: 2s

format:
  fix: true

analyze:
  scope: affected
  fail_on: [error, warning]

codegen:
  generated_files_committed: true

pubspec:
  monotonic_build_number: [release/*]

assets:
  max_file_size: 500KB
  ignore: [assets/videos/**]

baseline: .stagelatch/baseline.json
```

## 3. Keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `min_version` | version | none | Exit 78 when the running tool is older |
| `hooks.pre-commit` | list of selectors | all pre-commit checks of the running version, in the order shown above | What runs on commit |
| `hooks.pre-push` | list of selectors | `[analyze, tests/affected]`, limited to what the running version implements | What runs on push |
| `hooks.ci` | list of selectors | union of the two lists above, pre-commit order first | What `ci` runs |
| `rules` | map of rule ID to level | `{}` | Severity override: `error`, `warning`, `off` |
| `exclude` | list of globs | `[]` | Paths that never produce findings |
| `sdk_path` | path | none | SDK root; see [`dart-toolchain.md`](dart-toolchain.md#1-sdk-resolution) |
| `time_budget` | duration | `2s` | Reported when exceeded; never skips anything |
| `format.fix` | bool | `true` | Apply formatting to the index on pre-commit |
| `analyze.scope` | `changed`, `affected`, `all` | `affected` | Which files are analyzed |
| `analyze.fail_on` | list of `error`, `warning`, `info` | `[error, warning]` | Analyzer severities that block |
| `codegen.generated_files_committed` | bool | `true` | `false` disables `codegen/stale` |
| `codegen.generated_suffixes` | list of strings | `[.g.dart, .freezed.dart]` | Suffixes that mark a generated part file |
| `pubspec.monotonic_build_number` | list of branch globs | `[]` | Branches where `pubspec/build-number-regression` applies |
| `pubspec.require_sha` | bool | `false` | `pubspec/unpinned-git` also rejects refs that are not a 40-character SHA |
| `assets.max_file_size` | size | `500KB` | Limit for `assets/max-file-size` |
| `assets.roots` | list of directories | `[assets/]` | Where `assets/undeclared` and `assets/max-file-size` look |
| `assets.ignore` | list of globs | `[]` | Asset paths exempt from all `assets` rules |
| `tests.functions` | list of identifiers | `[test, testWidgets, group]` | Calls inspected by `tests/solo` and `tests/new-skip` |
| `baseline` | path | `.stagelatch/baseline.json` | Baseline file; a missing file is an empty baseline |

## 4. Value syntax

- **Selector:** `<check>` or `<check>/<rule>` (ADR-0009). `<check>` enables all rules of that check. Order in the list is irrelevant to execution; checks run in registry order.
- **Rule ID:** `<check>/<rule>`. Must exist in the running version, except under `analyze/`, where any name is accepted.
- **Level:** `error`, `warning`, `off`. YAML parses a bare `off` as the boolean `false`; the loader accepts boolean `false` as `off` and rejects boolean `true`.
- **Glob:** `package:glob` syntax, matched against the repository-relative path with forward slashes. `**` crosses directories. Matching is case-sensitive on every platform.
- **Branch glob:** same syntax, matched against the short branch name (`release/1.2`).
- **Size:** a non-negative integer followed by `B`, `KB` or `MB`. `1KB` is 1024 bytes, `1MB` is 1024 KB.
- **Duration:** an integer followed by `ms`, or a decimal number followed by `s`. Must be greater than zero.
- **Version:** a pub semantic version, e.g. `0.1.0` or `0.1.0-dev.1`.
- **Path:** relative paths are resolved against the repository root.

## 5. Validation

The file is validated completely before any check runs. The first problem found, in document order, is reported and the run exits 78. One exception: `min_version` is checked before everything else, wherever it is written, so that a tool that is too old says so instead of complaining about checks it does not know yet.

```
stagelatch.yaml:12:3: Unknown key "forbid" under "pubspec".
```

| Problem | Message |
|---|---|
| Not valid YAML | `stagelatch.yaml:<l>:<c>: <parser message>` |
| Root is not a map | `stagelatch.yaml:1:1: Expected a map at the top level.` |
| Unknown key in a section | `Unknown key "<key>" under "<section>".` |
| Unknown key at the root | `Unknown key "<key>" at the top level.` |
| Wrong type | `"<key>" must be <type>, found <actual>.` Types: `a map`, `a list`, `a list of strings`, `a string`, `a boolean`. Actual: `a map`, `a list`, `a string`, `a number`, `a boolean`, `null`. Keys inside a section are written with a dot: `format.fix`. |
| Unknown check in a selector | `Unknown check "<name>" in hooks.<hook>.` |
| Unknown rule, in a selector or in `rules` | `Unknown rule "<id>".` |
| Invalid level | `Level of "<id>" must be error, warning or off.` |
| Invalid value | `Invalid <kind> "<value>" in "<key>".` Kinds: `selector`, `glob`, `size`, `duration`, `version`, `scope`, `severity`, `directory`, `identifier`, `path`. A bare number is read as its text, so `max_file_size: 500` is an invalid size, not a type error. |
| Unknown hook name under `hooks` | `Unknown hook "<name>". Expected pre-commit, pre-push or ci.` |
| Duplicate key | `Duplicate mapping key.` (reported by the YAML parser, at the second occurrence) |
| Reserved key | `custom_checks requires stagelatch >= 1.0.0.` |

A section, list or map written without a value (`format:` alone on a line) keeps its defaults.
| Tool too old | `This repository requires stagelatch >= <min>; you have <current>. Run: dart pub global activate stagelatch` |

Unknown keys are errors on purpose: a typo must not silently disable a rule.

## 6. Defaults without a config file

Every default in section 3 applies. `init` writes those defaults explicitly, trimmed to what it detected, so the committed file documents the team's choices.

## 7. JSON Schema

Since `0.2.0`, `schema/stagelatch.schema.json` describes this file for editors. A test loads the schema and asserts that it accepts the full example above and that every key of section 3 appears in it with the documented type.

## 8. In-code model

`application/config/config.dart` holds an immutable `Config` with one typed settings class per check (`FormatSettings`, `AnalyzeSettings`, `CodegenSettings`, `PubspecSettings`, `AssetsSettings`, `TestsSettings`). `CheckContext.settings<T>()` returns the one a check asks for. Globs, sizes and durations are parsed once, at load time.

# CLI specification

Status: **Approved (2026-11-12).**

## 1. Invocation

```
stagelatch [global options] <command> [options]
```

| Global option | Meaning |
|---|---|
| `-h`, `--help` | Print usage; exit 0 |
| `--version` | Print `stagelatch <version>`; exit 0 |
| `-C`, `--directory <path>` | Run as if started in `<path>`. Default: current directory |
| `--[no-]color` | Force color on or off. Default: on only when stdout is a terminal and `NO_COLOR` is unset |
| `--verbose` | Print diagnostics (commands run, timings, stack traces) to stderr |

Rules that hold for every command:

- Reports go to stdout. Errors about the invocation, and all `--verbose` output, go to stderr.
- No command prompts (ADR-0011).
- Console output is ASCII only. Repository-derived text is passed through the control-character sanitizer (security S5).
- Running outside a git work tree is a usage error: `Not inside a git work tree: <path>.`

## 2. Exit codes

| Code | Name | When |
|---|---|---|
| 0 | `pass` | No blocking finding; or the command succeeded |
| 1 | `findings` | At least one finding with severity `error`; or `doctor` found a failure |
| 64 | `usage` | Bad arguments, not a repository, shallow clone without merge base, third-party hook without `--force`, missing package config |
| 70 | `internal` | Unexpected failure: a bug, or a git command that failed unexpectedly |
| 78 | `config` | Invalid `stagelatch.yaml`, or tool older than `min_version` |

Internal error output, on stderr, exactly:

```
stagelatch: internal error in <where>: <message>
This is a bug in stagelatch, not in your change.
To proceed anyway: git commit --no-verify
Report it: https://github.com/danielcbdev/stagelatch/issues
```

`<where>` is `check "<id>"` or the command name. The third line is printed only for `run`. The stack trace follows with `--verbose`.

## 3. Commands

### 3.1 `init [--force] [--no-hooks]`

Since `0.1.0-dev.1`.

1. Detect: Flutter or pure Dart (a `flutter` SDK dependency in any `pubspec.yaml`), FVM (`.fvmrc` or `.fvm/`), code generation (`build_runner` in `dev_dependencies`), l10n (`l10n.yaml`), assets (a `flutter: assets:` section).
2. Write `stagelatch.yaml` at the repository root, listing in `hooks` only checks that exist in the running version and are relevant to what was detected. Refuse to overwrite an existing file without `--force` (exit 64): `stagelatch.yaml already exists. Use --force to overwrite.`
3. Unless `--no-hooks`, run `install`.

Output: one line per action, e.g. `Created stagelatch.yaml.`, then the lines of `install`.

### 3.2 `install [--force]`

Since `0.1.0-dev.1`. Installs one script per key under `hooks` that is a git hook name (`pre-commit`, `pre-push`). Behavior per hook is the matrix in [`git.md`](git.md#hook-installer). Output per hook, one of:

- `Installed <hook> hook at <path>.`
- `Updated <hook> hook at <path>.`
- `<hook> hook is already up to date.`
- `Replaced <hook> hook at <path>; backup saved to <backup>.` (with `--force`)

Refusal (exit 64), on stderr:

```
A <hook> hook that stagelatch does not manage already exists at <path>.
Add this line to it, or re-run with --force to replace it (a backup is kept):
  stagelatch run <hook> "$@"
```

### 3.3 `uninstall`

Since `0.1.0-dev.1`. For each git hook name: remove the script if it carries the managed marker, then restore the most recent backup if one exists. Never touches an unmanaged hook. Output: `Removed <hook> hook.`, `Restored <hook> hook from <backup>.`, or `No managed <hook> hook found.` Always exits 0 unless a file operation fails.

### 3.4 `run <hook> [--all] [--no-fix] [--reporter <console|json>] [-- <hook args>]`

`pre-commit` since `0.1.0-dev.1`; `pre-push` and `--reporter json` since `0.1.0`; `--all` since `0.2.0`.

- `<hook>` is `pre-commit` or `pre-push`; anything else is a usage error.
- Runs the pipeline for that entry point ([`architecture.md`](../architecture.md#53-the-pipeline)).
- `--no-fix` disables fix application for this run regardless of config.
- `--all` ignores the changeset and treats every file of the snapshot as changed.
- **`pre-push` input.** Git passes the remote name and URL as arguments and one line per ref on stdin: `<local ref> <local sha> <remote ref> <remote sha>`. When stdin is a terminal or empty, one ref is synthesized from the current branch and its upstream (remote sha all zeros when there is no upstream).
- Exit: 0 or 1 by verdict; 64/70/78 as in section 2.

### 3.5 `ci --base <ref> [--head <ref>] [--all] [--reporter <console|json|github|junit|sarif>]`

Since `0.1.0` (`junit`, `sarif` since `0.3.0`).

- `--base` is required. `--head` defaults to `HEAD`.
- Selectors come from `hooks.ci`, or the union of `hooks.pre-commit` and `hooks.pre-push`.
- Fixes are never applied.
- No merge base (typically a shallow clone), exit 64: `Cannot find a merge base between <base> and <head>. If this is a shallow clone, fetch full history (actions/checkout: fetch-depth: 0).`

### 3.6 `doctor [--reporter <console|json>]`

Since `0.1.0`. Runs these probes in order and prints one line each, prefixed `ok`, `warn` or `fail`:

| ID | Probe | `fail` when |
|---|---|---|
| D1 | git is on PATH; version | git missing or older than 2.30 |
| D2 | inside a work tree | not |
| D3 | hooks directory, and whether `core.hooksPath` is set | never (`warn` when set) |
| D4 | each configured hook: managed, missing, or third-party | never (`warn` when missing or third-party) |
| D5 | how `stagelatch` resolves on PATH | never (`warn` when only the `dart pub global run` fallback works) |
| D6 | running version vs `min_version` | running version is older |
| D7 | `stagelatch.yaml` is valid | invalid |
| D8 | resolved SDK: path, version, source | no SDK found, or SDK inside the repository |
| D9 | `.dart_tool/package_config.json` per package | never (`warn` when missing) |

Exit 1 when any probe fails, else 0.

### 3.7 `baseline create [--force]`, `baseline prune`

Since `0.2.0`. Specified in [`baseline-and-suppression.md`](baseline-and-suppression.md#baseline-commands).

### 3.8 `why <test-file> [--base <ref>]`

Since `0.3.0`. Prints why `tests/affected` selects the test file for the changeset between `--base` (default: the upstream of the current branch, else its merge-base with the remote's default branch) and the index.

```
test/checkout/cart_test.dart is affected by 1 changed file:

lib/checkout/cart.dart (changed)
  imported by lib/checkout/cart_controller.dart
  imported by test/checkout/cart_test.dart
```

One shortest import chain per changed file that reaches the test. When none does: `test/x_test.dart is not affected by the current changes.` Exit 0 in both cases; exit 64 when the file is not a test file of any package.

## 4. Console reporter

Fixed layout. Golden files under `test/goldens/console/` are the byte-exact reference. A run has up to five sections, in this order: header, check table, details, notes, summary. Sections are separated by exactly one blank line, and a section with nothing to say is omitted, so two blank lines never appear in a row. Several runs of one invocation are separated the same way. With no run at all the whole report is `stagelatch: nothing to check.`

```
stagelatch pre-commit: 4 files

  format   fixed 1 file   41ms
  analyze  ok            870ms
  pubspec  1 error         6ms

lib/checkout/cart.dart  fixed  format/unformatted
pubspec.yaml:14:5  error  pubspec/path-dependency
  Dependency "design_system" uses a path that is not a package in this repository: ../design_system.

1 error, 0 warnings. Commit blocked. (0.9s)
```

- **Header:** `stagelatch <entry>: <n> file(s)`. `<entry>` is `pre-commit`, `pre-push <branch>` or `ci`.
- **Check table:** one row per check that ran, in registry order, indented two spaces. Three columns, separated by two spaces: id and status aligned left, duration aligned right. Each column is as wide as its widest cell. Status is `<e> error(s)`, `<w> warning(s)`, or both joined by `, ` when the check still has findings; otherwise `fixed <n> file(s)` when it fixed something; otherwise `ok`. Duration is `<n>ms` below one second, else `<n.n>s` (nearest tenth, integer arithmetic).
- **Details:** fixes first, then findings, with no blank line between them. One line per applied fix: `<path>  fixed  <rule>`. When the working tree was not updated, the next line is `  Fixed in the index only: the working tree copy has unstaged changes.` Findings are printed in the order the pipeline sorted them. Two lines each: `<path>:<line>:<column>  <severity>  <rule>` and the message indented two spaces.
- **Notes:** `note: <text>`, one per line. The budget note, when the budget was exceeded, comes after the other notices: `note: Time budget of <budget> exceeded (<total>).` `<budget>` is whole seconds as `<n>s` and anything else as `<n>ms`. `<total>` is seconds with one decimal.
- **Summary:** `<e> error(s), <w> warning(s). <Outcome>. (<total>)`. Outcome is `Commit blocked`/`Commit allowed`, `Push blocked`/`Push allowed`, or `Failed`/`Passed`. When anything was suppressed or baselined, a second line: `(<n> suppressed, <m> baselined)`.
- Singular and plural: `1 file`, `2 files`; `1 error`, `0 errors`.
- With color: `error` red (31), `warning` yellow (33), rule ids dim (2), then reset (0). Color never changes the text.
- Every string that came from the repository (path, message, branch name, notice) is passed through `sanitizeForTerminal` first. C0, DEL, C1 and the bidirectional controls U+200E, U+200F, U+202A–U+202E and U+2066–U+2069 are removed; newline and tab become a space.

## 5. JSON reporter

One JSON object, UTF-8, followed by a newline. Keys appear in this order. `schemaVersion` changes only on a breaking change.

```json
{
  "schemaVersion": 1,
  "stagelatchVersion": "0.1.0",
  "entry": "pre-commit",
  "verdict": "fail",
  "exitCode": 1,
  "files": 4,
  "findings": [
    {
      "rule": "pubspec/path-dependency",
      "severity": "error",
      "path": "pubspec.yaml",
      "line": 14,
      "column": 5,
      "endLine": 14,
      "endColumn": 26,
      "message": "Dependency \"design_system\" uses a path that is not a package in this repository: ../design_system."
    }
  ],
  "fixes": [
    {"rule": "format/unformatted", "path": "lib/checkout/cart.dart", "worktreeUpdated": false}
  ],
  "checks": [
    {"id": "format", "durationMs": 41, "errors": 0, "warnings": 0, "fixed": 1}
  ],
  "suppressed": 0,
  "baselined": 0,
  "notices": [],
  "durationMs": 917,
  "timeBudgetExceeded": false
}
```

- Lines and columns are 1-based. `path` is repository-relative with forward slashes.
- With several pre-push refs, the object has `"runs": [ ... ]`, each element shaped as above without `schemaVersion` and `stagelatchVersion`, plus top-level `verdict` and `exitCode`.
- Everything except `durationMs` fields is deterministic (ADR-0003).
- On exit 64, 70 or 78 the JSON reporter prints `{"schemaVersion":1,"error":{"kind":"usage|internal|config","message":"..."},"exitCode":N}` to stdout, and the human message to stderr.

## 6. GitHub reporter

One workflow command per finding, then the console summary line.

```
::error file=pubspec.yaml,line=14,col=5,endLine=14,endColumn=26,title=pubspec/path-dependency::Dependency "design_system" uses a path that is not a package in this repository: ../design_system.
```

- `::error` for errors, `::warning` for warnings.
- Message data (after the second `::`) escapes `%` as `%25`, `\r` as `%0D`, `\n` as `%0A`. A `:` there is left as is.
- Property values (`file`, `title`) additionally escape `:` as `%3A` and `,` as `%2C`.

## 7. SARIF and JUnit reporters

Since `0.3.0`.

- **SARIF 2.1.0:** one `run`; `tool.driver.name` is `stagelatch`; `rules` lists every rule that produced a result, with `id` and `shortDescription`; each finding is a `result` with `ruleId`, `level` (`error` or `warning`), `message.text` and one `physicalLocation` using 1-based `region`.
- **JUnit XML:** one `<testsuite name="stagelatch">`; one `<testcase>` per check with `classname="stagelatch"` and `name="<check id>"`; each error finding is a `<failure>` whose `message` is `<rule>: <message>` and whose text is `<path>:<line>:<column>`. Warnings go to `<system-out>`.

# stagelatch

A *change-aware* quality gate for Flutter and Dart repositories. One engine with two entry points:

- **Local hook:** pre-commit and pre-push.
- **CI:** pull request.

It judges the exact snapshot being published (the **index** at pre-commit, the pushed commit at pre-push, the PR head in CI), with Dart semantics and only within the affected scope.

Distributed as a CLI on pub.dev (`dart pub global activate stagelatch`). Portfolio project: engineering quality, documented decisions and solved edge cases matter more than the number of features.

## Documentation

Before implementing anything, read [`docs/README.md`](docs/README.md) and follow its reading order: architecture, engineering standards, specs and the current plan in `docs/plans/`. The branch and pull request flow is in `docs/engineering/workflow.md`.

Precedence: this file > ADRs > specs > plans. The documentation and the refinements listed in `docs/specs/README.md` were approved on 2026-11-12 and are already reflected here.

## Language

- Conversation with the owner: Portuguese, direct, no preamble.
- In English: code, identifiers, comments, commit messages, README, CHANGELOG, public docs and CLI messages.

## Fixed decisions (recorded in `docs/adr/`)

1. **Validate the index, not the working tree.**
   - Blobs are read by one persistent `git cat-file --batch` process: one spawn, not one per file.
   - Analysis runs on the materialized snapshot: the snapshot's `.dart`, `.yaml` and `.yml` files are written from the blobs into a fresh temporary directory, with each package's `.dart_tool/package_config.json` copied and rewritten, and the resolved SDK's analysis server (`dart language-server --protocol=analyzer`) analyzes that directory. Unstaged changes, untracked files and deletions that exist only in the index stay invisible. Measured cost: ~0.25 s for 2,472 files.
   - Overlays on top of the working tree were rejected (2026-11-19): the server reads from disk everything that is not in the overlay, so an untracked file imported by a staged file made the gate pass.
   - Formatting goes through the same SDK's `dart format --stdin-name`, with the blob on stdin.
   - Never use stash.
2. **Safe autofix.**
   - It writes the corrected blob to the index (`git hash-object -w --stdin` + `git update-index --cacheinfo <mode>,<sha>,<path>`).
   - It rewrites the file on disk only if the file has no unstaged changes.
3. **Deterministic. No AI in the blocking path.**
   - No network.
   - Same input, same result on any machine and in CI.
   - The time budget only **warns** when exceeded. It never skips or shortens a check, because that would make the verdict depend on the machine.
4. **Distributed through `pub global activate`, never as a dev_dependency.** The `analyzer` would enter the project's version solving and conflict with freezed, json_serializable and build_runner.
5. **Same engine for hook and CI.**
   - The local hook is fast feedback.
   - The guarantee is `stagelatch ci` on the pull request.
6. **Hooks are thin triggers with no logic.** The only logic allowed is locating the executable. If it is not installed, the hook warns and **does not block**, because CI is the guarantee:
   ```sh
   #!/bin/sh
   # stagelatch:managed
   if command -v stagelatch >/dev/null 2>&1; then
     exec stagelatch run pre-commit "$@"
   elif command -v stagelatch.bat >/dev/null 2>&1; then
     exec stagelatch.bat run pre-commit "$@"
   elif command -v dart >/dev/null 2>&1 &&
     dart pub global list 2>/dev/null | grep -q '^stagelatch '; then
     exec dart pub global run stagelatch run pre-commit "$@"
   fi
   echo "stagelatch not found; skipping. Install: dart pub global activate stagelatch" >&2
   exit 0
   ```
   The two fallbacks exist because of Windows (see risks). The final form of the template is the one that passes the acceptance test on the Windows runner.
7. **Snapshot and changeset per entry point.**

   | Entry point | Snapshot | Changeset |
   |---|---|---|
   | pre-commit | index | index vs HEAD (first commit: vs empty tree) |
   | pre-push | pushed commit, read from the hook's stdin (`<local ref> <local sha> <remote ref> <remote sha>`) | `<remote sha>..<local sha>` |
   | `ci` | PR head | `merge-base(--base, HEAD)..HEAD` |

   - Analysis follows decision 1 for any snapshot: the materialized directory holds the files of that snapshot, whether it is the index or a commit.
   - **Pre-push of a new branch** (zeroed `<remote sha>`): the base is the merge-base with all branches of that remote (`refs/remotes/<remote>/*`); with none, the empty tree. Branch deletion (zeroed `<local sha>`) and tag pushes have nothing to validate.
   - **Merge in progress** (`MERGE_HEAD` exists): the changeset is only what differs from **both** parents, that is, conflict resolutions and manual edits. What came untouched from the other branch has already passed that branch's CI.
   - **Rebase in progress:** when the hook fires, it uses the normal changeset (index vs HEAD).
   - **Shallow clone in CI** with no reachable merge-base: fails with a clear message asking for `fetch-depth: 0`. It never analyzes a wrong diff.
8. **Parity with the project's SDK.**
   - `format` and `analyze` must give the same result as the `dart format` and `dart analyze` of the SDK the team uses. A divergence is a bug.
   - SDK resolution, in this order: `sdk_path` from the config, FVM (`.fvmrc`, `.fvm/flutter_sdk`), `dart` on PATH.
   - The resolved SDK must be outside the repository's working tree: `sdk_path` and `.fvm/` are repository content and must not point to a versioned binary.
   - No `.dart_tool/package_config.json` when Dart analysis is needed: usage error (exit 64) asking for `dart pub get`.
   - Mechanism, decided in the spike (`docs/spike/report.md`): delegate to the resolved SDK, one process per run. Diagnostics come from the analysis server; formatting from `dart format --stdin-name`. The tool depends on neither `analyzer` nor `dart_style`, and its SDK floor stays at `^3.13.0`. The parity test compares against the SDK's `dart analyze` and `dart format`.
   - `analyze` costs one server start per run (about 1 s on a pure Dart package, 13 s on a 2,400-file Flutter app). That is why it sits in `pre-push` and `ci` by default, outside `pre-commit`.
   - Analyzer plugins and `custom_lint` have no guaranteed execution. This is a documented limitation, not a bug.
9. **One vocabulary: the rule ID.**
   - `<check>/<rule>` is the only notation, used in hooks, `rules:`, ignore, baseline and reporters.
   - A hook's list accepts `<check>` (all rules of the check) or `<check>/<rule>`.
   - Severity is configured only in the `rules:` map (`error`, `warning`, `off`). Per-check sections hold parameters only.
10. **Explicit, localized suppression.**
    - Comment `// stagelatch:ignore <rule-id>` in Dart and `# stagelatch:ignore <rule-id>` in YAML, on the finding's line or the previous one. The ID is mandatory; there is no generic ignore.
    - `exclude` by glob in the config, for whole paths.
    - `analyze` honors the analyzer's own `// ignore:` comments and `analysis_options.yaml`.
11. **Never interactive without a TTY.**
    - No command opens a prompt when stdin or stdout is not a TTY; `init` proceeds with the detected defaults.
    - No color output outside a TTY or when `NO_COLOR` is set.
    - Reason: hooks, CI and AI agents hang on any interactive question.
12. **Ports and adapters in five modules.** `domain`, `checks`, `application`, `infrastructure`, `cli`. Dependencies point inward, `dart:io` exists only in `infrastructure` and `cli`, and an architecture test breaks the build on a forbidden import.
13. **Checks consume facts, not ASTs.** `DartFileFacts` (directives, annotated declarations, test calls) is purely syntactic and cacheable by blob id. A hand-written lexer, with no `analyzer`, extracts the facts (ADR-0017): 0 disagreements against `parseString` on 2,462 files, 13 times faster on the 10 files of a commit and linear on hostile input.
14. **Two-phase pipeline: fix, then verify.** Fixes enter the index before the other checks, so every location refers to the content that will be committed.
15. **Config and baseline come from the snapshot,** not from the working tree. A config present only in the working tree is used with a warning.
16. **Branch flow.** One branch per plan task from `develop`, pull request, green CI, squash-merge. Release through a `develop` → `main` pull request with a merge commit.

## Architecture

```
lib/src/
├── domain/          # Check, Finding, Severity, Location, ChangeSet, Fix — no dependency on git/analyzer/IO
├── checks/          # one folder per check; imports only the domain
├── application/     # Pipeline, per-hook check selection, scheduler, time budget, Baseline, ConfigLoader
├── infrastructure/  # GitClient, SdkDartToolchain (analysis server + dart format), facts extractor (lexer), PubspecReader, SdkLocator, reporters, HookInstaller
└── cli/             # commands (package:args CommandRunner)
```

- Checks receive a `CheckContext` (blob reading, analyzer session, parsed pubspec, config) and return findings. They know nothing about git, the analyzer or IO directly.
- Rule IDs use the format `<check>/<rule>`, for example `pubspec/path-dependency`. They are stable, documented and used in config, ignore and baseline.
- Baseline fingerprint: `ruleId + path + hash of the normalized snippet`. Never a line number.
- Locations carry line and column. YAML is read with `package:yaml`, preserving source spans.
- Package discovery: each file belongs to the nearest `pubspec.yaml` above it, with one analysis context per package. Pub workspaces only in `0.3.0`.
- `HookInstaller`:
  - resolves the hooks directory with `git rev-parse --git-path hooks`, which already honors `core.hooksPath` (husky and lefthook change it) and linked worktrees, where hooks live in the main repository;
  - does not overwrite third-party hooks without `--force`, and makes a backup when it does overwrite;
  - on `uninstall`, removes only hooks marked `stagelatch:managed` and restores the backup, if any.

## CLI

| Command | Purpose | Since |
|---|---|---|
| `stagelatch init` | detects the stack, generates `stagelatch.yaml`, installs hooks | `0.1.0-dev.1` |
| `stagelatch install` | installs hooks only (per clone) | `0.1.0-dev.1` |
| `stagelatch uninstall` | removes managed hooks and restores backups | `0.1.0-dev.1` |
| `stagelatch run <hook>` | runs the hook's checks on its snapshot (decision 7) | `pre-commit` in `0.1.0-dev.1`, `pre-push` in `0.1.0` |
| `stagelatch ci --base <ref> --reporter <console\|json\|github\|junit\|sarif>` | same engine over the PR diff | `0.1.0` |
| `stagelatch doctor` | diagnoses hooks, `core.hooksPath`, resolved SDK, PATH and `min_version` | `0.1.0` |
| `stagelatch baseline create\|prune` | adoption in a legacy project | `0.2.0` |
| `stagelatch why <test-file>` | explains the affected-test selection | `0.3.0` |

`run` and `ci` accept `--all` (since `0.2.0`), which ignores the changeset and sweeps the whole snapshot. It is what `baseline create` uses.

`run` and `ci` accept `--reporter json` (since `0.1.0`): the list of findings with rule, severity, path, line, column, message and applied fix, plus the time of each check. It is the output for scripts and AI agents, which should not parse terminal text.

Exit codes:

| Code | Meaning |
|---|---|
| `0` | passed |
| `1` | blocking findings |
| `64` | incorrect usage |
| `70` | internal error |
| `78` | invalid config |

## Config (`stagelatch.yaml`)

```yaml
min_version: 0.1.0

hooks:
  pre-commit: [format, codegen, pubspec, l10n, assets, sensitive-files, tests/solo, tests/new-skip]
  pre-push: [analyze, tests/affected]
  # ci: optional; defaults to the union of the two lists above.

# Severity per rule: error | warning | off. Omitted rules keep their default.
rules:
  l10n/unused-key: warning
  tests/new-skip: warning
  pubspec/unpinned-git: off

# Paths that never produce findings.
exclude: [lib/generated/**]

# Optional. Default resolution: FVM, then `dart` on PATH.
# sdk_path: .fvm/flutter_sdk

# Reported when exceeded. Never skips a check.
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

The schema is published as a JSON Schema (`0.2.0`) for editor autocomplete.

All keys, defaults and validations are in `docs/specs/config.md`, including `analyze.scope` (`changed`, `affected`, `all`), `codegen.generated_suffixes`, `pubspec.require_sha`, `assets.roots` and `tests.functions`. Sizes use binary units: `1KB` is 1024 bytes.

## Rule catalog

| Check | Rules |
|---|---|
| `format` | `unformatted` |
| `analyze` | the analyzer diagnostic's code |
| `codegen` | `stale`: AST diff HEAD vs index of annotated declarations without the matching `.g.dart`/`.freezed.dart` staged |
| `pubspec` | `path-dependency` (only when the target is not a package of this repository), `dependency-overrides`, `unpinned-git`, `build-number-regression`, `lockfile-out-of-sync` (the lock does not satisfy the declared constraints), `unparseable` |
| `l10n` | `missing-key`, `placeholder-mismatch`, `unused-key`, `unparseable` (reads `l10n.yaml`) |
| `assets` | `missing`, `undeclared`, `max-file-size` |
| `sensitive-files` | `signing` (`key.properties`, keystores, `.p8`/`.p12`), `credentials` (service account JSON, `.env*`) |
| `tests` | `solo`, `new-skip` (only a skip introduced in the changeset, never old ones), `affected` (pre-push and CI; does not run if the affected files have uncommitted changes) |
| `stagelatch` | `invalid-ignore`: unknown ID in a `stagelatch:ignore` comment |

Default severity: `error`, except `l10n/unused-key`, `tests/new-skip` and `stagelatch/invalid-ignore`, which are `warning`. Trigger, exact message and location of each rule are in `docs/specs/rules.md`.

## Roadmap

0. **Spike (completed on 2026-11-19, `docs/spike/report.md`).**
   - It measured the embedded `analyzer` (with `OverlayResourceProvider`) and the SDK's analysis server on a real 2,435-file Flutter app, on commits of 3 and 10 files, through the real path (`pub global activate`), cold and warm.
   - The embedded one failed parity: the pub.dev `analyzer` does not ship the lint rules. The server passed parity and took ~13.6 s; a daemon would take ~2.5 s with 3 GB of RAM.
   - Owner's decision: one server per run, formatting through `dart format --stdin-name`, `analyze` outside the default `pre-commit`, no daemon in `0.1.0` (decision 8).
1. **`0.1.0-dev.1`**, to reserve the name on pub.dev; deliberately without the analyzer.
   - `init`, `install`, `uninstall`, `run pre-commit`.
   - `GitClient` with `cat-file --batch`.
   - Checks `pubspec/path-dependency`, `pubspec/dependency-overrides` and `pubspec/unparseable`.
   - Console reporter.
   - Hook with a Windows fallback, validated by a real `git commit` on the Windows runner.
   - Non-interactive commands outside a TTY and correct hook installation in a linked worktree.
   - Acceptance tests.
2. **`0.1.0`**
   - `format` with safe autofix.
   - `analyze` on the affected scope over the materialized snapshot and the import graph (built here and reused in `0.3.0`).
   - `sensitive-files`.
   - `run pre-push` on the pushed commit.
   - `ci --base` with the `github` reporter, and a composite action (`action.yml`) that installs and runs `ci`.
   - SDK resolution (`sdk_path`, FVM) and package discovery through the nearest `pubspec.yaml`.
   - `rules:` map, `exclude` and `stagelatch:ignore` comments.
   - `doctor`.
   - `json` reporter.
   - Reproducible benchmark in the README and a terminal GIF recorded with VHS.
3. **`0.2.0`:** `codegen`, `l10n` (without `unused-key`), `assets`, full `pubspec` with `lockfile-out-of-sync`, `tests/solo`, `tests/new-skip`, baseline, `--all`, JSON Schema of the config.
4. **`0.3.0`:** `tests/affected` (over the import graph from `0.1.0`), `why`, `l10n/unused-key` (the only rule that sweeps the whole project; it reuses the graph and the cache), content-hash cache, SARIF and JUnit reporters, pub workspaces.
5. **`1.0.0`:** Out-of-process custom checks (`protocol: 1`, ADR-0019). No `stagelatch_core` package in this version: guide + `example/custom_check/`. The public Dart API remains only `packageVersion`. Spec approved by the owner on 2026-11-21 (PR #87) in `docs/specs/custom-checks.md`; contract in force in `docs/stability.md`. Released on 2026-11-21.

## Out of scope

- Content-based secret scanning. `sensitive-files` looks at the path and the file's structure; gitleaks covers the rest.
- Commit message lint (`commit-msg` hook).
- Running analyzer plugins and `custom_lint`.
- Telemetry and update checks (they would require network).
- Daemon in `0.1.0`. The spike did not reach the goal and the owner chose a single execution per run; a daemon later needs its own ADR and an amendment to S7.

## Engineering standards

- **SDK:** the tool requires Dart `^3.13.0`.
- **Lints:** `very_good_analysis` with `strict-casts`, `strict-inference` and `strict-raw-types`. Zero warnings.
- **Console output:** ASCII only.
- **Tests:**
  - Unit tests in the domain and the application.
  - **Acceptance tests with real git repositories** created in a temporary directory.
  - Mandatory scenarios:
    - partial staging (`git add -p`);
    - rename, delete, binary file;
    - first commit (no HEAD);
    - merge and rebase in progress, including the merge's reduced changeset;
    - pre-push of a new branch and of a branch deletion;
    - `ci` in a shallow clone;
    - `core.hooksPath` already set by another tool;
    - linked worktree (`git worktree add`);
    - run without a TTY (no prompt, no color output);
    - hook fired by a real `git commit` on Windows;
    - CRLF;
    - paths with spaces and unicode.
- **CI:** Dart stable and beta × ubuntu, macos and windows matrix.
- **Release:**
  - Conventional Commits.
  - `release-please` for version and CHANGELOG.
  - Publishing to pub.dev through GitHub Actions with OIDC, no stored token.
- **Performance:** pre-commit should run in 1-2 s. Measure and report the time of each check.

## Known risks to verify early

- **Windows:** `pub global activate` generates `stagelatch.bat`, and the hook runs in Git for Windows' `sh`, which may not resolve `.bat`. The template in decision 6 handles this with two fallbacks; it still has to be proven on the Windows runner, in `0.1.0-dev.1`.
- **SDK parity:** solved by construction (decision 8): diagnostics and formatting come from the project's SDK.
- **JIT startup:** the activated executable takes ~0.8 s just to start. Little is left of the 1-2 s `pre-commit` budget, which is why `analyze` left it.
- **Analysis server protocol:** the legacy protocol may change between SDKs. The contract test runs on Dart stable and beta in CI, and the parity test on two Flutter SDKs.
- **Codegen:** respect projects that do **not** version generated files (`generated_files_committed: false`).

# Specifications

Status: **Approved (2026-11-12).** Specs say what the software must do, with exact values. Plans say how to build it.

| Spec | Covers |
|---|---|
| [`cli.md`](cli.md) | Commands, flags, exit codes, console/JSON/GitHub output |
| [`config.md`](config.md) | `stagelatch.yaml`: every key, default and validation rule |
| [`rules.md`](rules.md) | Every rule: trigger, detection, message, location, severity |
| [`git.md`](git.md) | Snapshots, changesets, index fixes, hook script, hook installer |
| [`dart-toolchain.md`](dart-toolchain.md) | SDK resolution, packages, overlays, diagnostics, formatting, facts |
| [`baseline-and-suppression.md`](baseline-and-suppression.md) | Inline ignores, `exclude`, baseline file and fingerprint |
| [`custom-checks.md`](custom-checks.md) | Draft of the 1.0.0 public API |

## Feature to version map

| Version | Delivered | Plan |
|---|---|---|
| spike | Latency and parity measurements; mechanism of ADR-0008 | [`00`](../plans/00-spike.md) |
| `0.1.0-dev.1` | `init`, `install`, `uninstall`, `run pre-commit`; `pubspec/path-dependency`, `pubspec/dependency-overrides`, `pubspec/unparseable`; console reporter | [`01`](../plans/01-foundation.md) |
| `0.1.0` | `format`, `analyze`, `sensitive-files`; `run pre-push`; `ci`; `doctor`; JSON and GitHub reporters; SDK resolution; multi-package; `rules:`, `exclude`, inline ignore | [`02`](../plans/02-core.md) |
| `0.2.0` | `codegen`, `l10n` (no `unused-key`), `assets`, rest of `pubspec`, `tests/solo`, `tests/new-skip`; baseline; `--all`; JSON Schema | [`03`](../plans/03-checks.md) |
| `0.3.0` | `tests/affected`, `why`, `l10n/unused-key`; cache; SARIF and JUnit; pub workspaces | [`04`](../plans/04-affected.md) |
| `1.0.0` | Custom checks | [`05`](../plans/05-public-api.md) |

## Refinements to CLAUDE.md

Writing the specs forced decisions that `CLAUDE.md` leaves open or states loosely. All of them were approved by the owner on 2026-11-12, and `CLAUDE.md` now reflects them. A later refinement is added to this table and stays pending until approved.

| # | Refinement | Where |
|---|---|---|
| R1 | Base of a newly pushed branch is the merge-base with **all** branches of that remote, not only the default branch. | ADR-0007 |
| R2 | `pubspec/path-dependency` flags a path dependency only when its target has no `pubspec.yaml` in the snapshot. Path dependencies between packages of the same repository are legitimate. | `rules.md` |
| R3 | `pubspec/lockfile-out-of-sync` verifies that the lock satisfies the declared constraints, instead of only checking that the lock file was staged. | `rules.md` |
| R4 | Three new rules: `pubspec/unparseable`, `l10n/unparseable`, `stagelatch/invalid-ignore`. | `rules.md` |
| R5 | `analyze.scope` takes `changed`, `affected` or `all`. `affected` needs the import graph, so the graph is built in `0.1.0` and reused by `tests/affected` in `0.3.0`. | `config.md`, `dart-toolchain.md` |
| R6 | New optional `hooks.ci` selector list; the default is the union of `pre-commit` and `pre-push`. | `config.md` |
| R7 | New config keys: `codegen.generated_suffixes`, `pubspec.require_sha`, `assets.roots`, `tests.functions`. | `config.md` |
| R8 | Config and baseline are read from the snapshot, not the working tree. | ADR-0015 |
| R9 | Pipeline runs in two phases: fix, then verify. | ADR-0014 |
| R10 | A fifth module, `checks`, separate from `domain`. | ADR-0012 |
| R11 | The resolved SDK must be outside the repository. | `security.md` S2 |
| R12 | Size units are binary: `1KB` = 1024 bytes. | `config.md` |
| R13 | Console output is ASCII only. | `cli.md` |
| R14 | `tests/affected` does not run when affected files have uncommitted changes; it reports a warning instead. | `rules.md` |
| R15 | Dart SDK floor of the tool itself: `^3.13.0`. | `coding-standards.md` |
| R16 | Custom checks (1.0.0) run as external processes speaking a JSON protocol. Draft only. | `custom-checks.md` |
| R17 | Missing `.dart_tool/package_config.json` when Dart analysis is needed is a usage error (exit 64) asking for `dart pub get`. | `dart-toolchain.md` |

## Open questions for the owner

The documentation was approved without explicit answers to these, so the stated default stands for each until the owner says otherwise.

1. **Spike corpus.** The benchmark must be reproducible, so it needs a public Flutter app pinned to a commit. The plan proposes choosing one in spike task 1; a private app of yours can be a second data point.
2. **Repository URL in messages.** Error output links to `https://github.com/danielcbdev/stagelatch/issues`. Confirm that this is the public home.
3. **License.** Plan 01 scaffolds a `LICENSE`; MIT is assumed.

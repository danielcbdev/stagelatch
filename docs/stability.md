# Stability contract (1.0.0)

Status: **Binding.** This document is the semver surface for the 1.x line.
Compatibility tests under `test/compat/1.0/` must keep passing on every later
release of 1.x. A breaking change to anything in §1 requires a new major
version (see [`engineering/workflow.md`](engineering/workflow.md) §3).

## 1. Covered by semver

| Artefact | What “stable” means | How `test/compat/1.0/` covers it |
|---|---|---|
| Config schema | Keys, types, defaults, what is rejected, and exit **78** for invalid config, as documented in `docs/specs/config.md` and `schema/stagelatch.schema.json`, including `custom_checks`. Validation **message text** is not frozen (console copy; see §2) | Load a frozen `stagelatch.yaml` fixture; assert parse success / reject / exit 78 for selected cases; do **not** assert exact validation strings |
| Rule IDs | Built-in `<check>/<rule>` strings; removing or renaming one is breaking. Analyzer diagnostic codes under `analyze/<code>` are **not** frozen (see §2) | Golden list of built-in rule ids |
| Exit codes | `0`, `1`, `64`, `70`, `78` with the meanings in `docs/specs/cli.md` | Invoke CLI fixtures; assert codes |
| JSON report | `schemaVersion: 1` document shape in `cli.md` §5 | Compare encoded report to a frozen JSON file after stripping durations |
| SARIF reporter | Shape produced for `ci --reporter sarif` (`cli.md` §7) | Frozen SARIF fixture |
| JUnit reporter | Shape produced for `ci --reporter junit` (`cli.md` §7) | Frozen JUnit fixture |
| Custom-check protocol | `protocol: 1` messages and error behaviour in `docs/specs/custom-checks.md` | Replay a frozen stdin/stdout transcript against the codec / host |
| Baseline file | `version`, entry fields and fingerprint algorithm in `baseline-and-suppression.md` | Round-trip a frozen `.stagelatch/baseline.json` |
| Managed hook contract | Presence of `# stagelatch:managed`; invocation `stagelatch run <hook> "$@"` (or the documented Windows fallbacks that still call that command); non-blocking exit when the tool is missing. Script **bytes** are not frozen: `install` may regenerate the template | Assert marker + invocation contract + skip-when-missing behaviour; do **not** byte-compare the whole script |

## 2. Explicitly out of scope

| Artefact | Why |
|---|---|
| Console reporter text | Human copy may change for clarity without a major |
| Config validation message text | Same class as console copy; keys/types/rejects/exit 78 stay in §1 |
| Managed hook script bytes | `install` regenerates; only the marker and invocation contract in §1 are frozen |
| Durations / timings | Machine-dependent; stripped before equality claims (ADR-0003) |
| Internal Dart API under `lib/src/` | Not exported; may move freely |
| `lib/stagelatch.dart` beyond `packageVersion` | No public check/authoring API in 1.0.0 (ADR-0004, ADR-0019). Adding exports later is a minor only if documented as additive; a custom-check Dart library would be a separate package decision |
| Analyzer diagnostic codes (`analyze/<code>`) | Come from the project's SDK; the set changes across SDK releases (ADR-0008) |
| Doctor probe wording | May improve without a major; probe ids (`D1`…) stay stable when present |
| Example code under `example/` | Illustrative; not a compatibility surface |

## 3. Public Dart library (1.0.0 answer)

`package:stagelatch/stagelatch.dart` exports **only** `packageVersion`. Authors of custom checks depend on the **protocol**, not on importing stagelatch. This preserves ADR-0004 (no version solving against the host project).

## 4. Process for change

- Additive, backwards-compatible config keys or protocol capabilities (negotiated) may ship in a minor.
- Removing or renaming a §1 artefact requires major and a migration note in the CHANGELOG.
- Compatibility tests are never deleted; new majors add `test/compat/<major>.0/` alongside older ones while those majors are supported.

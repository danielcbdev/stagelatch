# ADR-0009: Rule IDs as the only vocabulary

- Status: Accepted
- Date: 2026-11-11

## Context

An earlier draft of the config named the same thing three ways: `tests.solo` in hook lists, `path-dependencies` in `pubspec.forbid`, and `missing_keys` under `l10n`, while reports said `pubspec/path-dependency`. Users would have to learn a mapping that carries no information.

## Decision

- A rule is identified by `<check>/<rule>`, lowercase, with hyphens inside each part. Example: `pubspec/path-dependency`.
- That exact string is used in hook lists, the `rules:` map, `stagelatch:ignore` comments, the baseline file and every reporter.
- A hook list accepts `<check>` (all rules of the check) or `<check>/<rule>`.
- Severity is configured in one place: the `rules:` map, with `error`, `warning` or `off`.
- Per-check config sections hold parameters only, never severities or rule switches.
- Rule IDs are stable. Renaming one is a breaking change and needs a deprecation alias for one minor version.

## Consequences

- `analyze` rule names come from the analyzer (`analyze/unused_import`) and keep the analyzer's spelling, underscores included. `analyze` is the only check with dynamic rules.
- Config validation rejects an unknown rule ID with exit 78, except under `analyze/`.
- One table in [`specs/rules.md`](../specs/rules.md) documents every rule.

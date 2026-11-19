# ADR-0010: Explicit, localized suppression

- Status: Accepted
- Date: 2026-11-11

## Context

Every gate needs an escape hatch for legitimate exceptions. A blanket one ("ignore this file", "ignore everything here") hides new problems and is the first thing an automated agent reaches for.

## Decision

- Inline: `// stagelatch:ignore <rule-id>[, <rule-id>...]` in Dart and `# stagelatch:ignore <rule-id>[, ...]` in YAML. It applies to findings that start on the same line or on the next line.
- At least one rule ID is required. There is no bare ignore and no wildcard.
- Whole paths are excluded with `exclude` globs in the config.
- `analyze` also honors the analyzer's own `// ignore:` comments and `analysis_options.yaml`, since those are part of what `dart analyze` reports.
- Formats without comments (JSON, ARB, binary files) cannot be suppressed inline; use `rules:` or `exclude`.

## Consequences

- Every suppression is visible in the diff with the rule it silences.
- The suppression filter needs the snapshot text of the finding's file; it runs in the pipeline, not in checks.
- An ignore comment naming an unknown rule ID is itself reported, so typos do not silently disable nothing.

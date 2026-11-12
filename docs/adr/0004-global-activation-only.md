# ADR-0004: Distribution by global activation only

- Status: Accepted
- Date: 2026-11-11

## Context

As a `dev_dependency`, stagelatch's own dependencies would enter the host project's version solving. Analyzer-related packages are pinned tightly by freezed, json_serializable and build_runner, so conflicts would be routine and would block adoption.

## Decision

- stagelatch is installed with `dart pub global activate stagelatch`. It is never documented, tested or supported as a dependency of the project it checks.
- The team pins the tool through `min_version` in `stagelatch.yaml`.

## Consequences

- No version conflicts with the host project.
- The tool runs from the JIT snapshot that `pub global activate` builds, not an AOT binary. Startup cost is a first-order concern and is measured in the spike.
- The tool runs on whatever Dart is on PATH, which may differ from the project's SDK. ADR-0008 covers that.
- Each developer installs it once per machine; ADR-0006 keeps a missing install from blocking work.

## Alternatives rejected

- **`dev_dependency`:** version solving conflicts.
- **Prebuilt binaries per platform:** better startup, but adds a release matrix and a download step outside pub. May be revisited after 1.0.0.

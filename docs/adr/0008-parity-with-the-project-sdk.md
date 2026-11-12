# ADR-0008: Parity with the project SDK

- Status: Accepted; mechanism pending the spike
- Date: 2026-11-11

## Context

The tool runs on the Dart found on PATH. The project may pin another SDK, typically through FVM. Formatter output and diagnostics change between SDK releases. If the gate disagrees with the IDE and with `dart format`, developers lose trust in it.

Facts measured on 2026-11-11: `analyzer` 14.7.0 requires Dart `^3.13.0`; `dart_style` 3.1.14 requires `^3.11.0`. Embedding them ties the tool to one SDK generation.

## Decision

- `format` and `analyze` must produce the same result as `dart format` and `dart analyze` of the SDK the project uses. A difference is a bug.
- SDK resolution order: `sdk_path` in config, then FVM (`.fvm/flutter_sdk`, `.fvmrc`), then `dart` on PATH. The resolved SDK must be outside the repository working tree (see [`security.md`](../engineering/security.md)).
- Analyzer plugins and `custom_lint` are not guaranteed to run. This is a documented limitation.
- **The mechanism is chosen by the spike** between two candidates, both hidden behind the `DartToolchain` port:
  - **A, embedded:** `package:analyzer` with `OverlayResourceProvider`, and `package:dart_style`, running in-process.
  - **B, delegated:** the resolved SDK's analysis server (`dart language-server --protocol=analyzer`), using `analysis.updateContent` for overlays, `analysis.getErrors` for diagnostics and `edit.format` for formatting.

## Consequences

- No code outside `infrastructure/dart/` may reference `package:analyzer`, `package:dart_style` or the server protocol.
- The spike report amends this ADR with the chosen mechanism, the numbers, and the SDK floor that follows from it.
- Candidate B gives exact parity by construction and removes the tight analyzer dependency, at the cost of a process spawn. Candidate A avoids the spawn but needs a proven answer for projects on older SDKs.

## Alternatives rejected

- **Shell out to `dart analyze` and `dart format` on disk:** cannot see the index (ADR-0001).

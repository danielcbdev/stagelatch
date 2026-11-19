# ADR-0003: Deterministic verdicts, no AI, no network

- Status: Accepted
- Date: 2026-11-11

## Context

A gate that passes on one machine and fails on another stops being trusted and gets bypassed. The same is true of a gate whose answer changes from run to run.

## Decision

- The verdict is a pure function of: the snapshot, the base, the config in the snapshot, the resolved Dart SDK version and the stagelatch version.
- No AI model takes part in producing findings or the verdict.
- No network access, by the tool or by any dependency.
- The time budget (`time_budget`) only **reports** that it was exceeded. It never skips, shortens or reorders a check.
- Output order is defined by sorting, never by completion order.

## Consequences

- Durations appear in reports but are excluded from any equality claim: two runs produce byte-identical JSON once duration fields are removed. A test asserts exactly that.
- There is no update check and no telemetry.
- `tests/affected` executes project code and is therefore only as deterministic as the project's tests. It is the single documented exception and runs only where configured.

## Alternatives rejected

- **Skip slow checks when over budget:** makes the verdict depend on machine speed and load.
- **AI-assisted review in the hook:** non-reproducible, slow, and needs the network.

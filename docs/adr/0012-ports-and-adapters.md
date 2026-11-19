# ADR-0012: Ports and adapters with five modules

- Status: Accepted
- Date: 2026-11-11

## Context

Three things in this project are volatile or hard to test: the git CLI, the Dart toolchain (ADR-0008 leaves its mechanism open) and the terminal. Rule logic is the opposite: stable, pure and worth testing exhaustively. Mixing them would make rule tests need real repositories and would spread toolchain details across the codebase.

## Decision

- Five modules under `lib/src`: `domain`, `checks`, `application`, `infrastructure`, `cli`, with the import table in [`architecture.md`](../architecture.md#2-style-ports-and-adapters-five-modules).
- Dependencies point inward. `domain` imports nothing of ours. `checks` imports only `domain`.
- The outside world is reached through ports: interfaces declared in `domain` (consumed by checks) or `application/ports` (consumed by use cases) and implemented in `infrastructure`.
- Wiring happens in exactly one file, `cli/composition.dart`, by plain constructor calls.
- `dart:io` is allowed only in `infrastructure` and `cli`.
- A test, `test/architecture/layering_test.dart`, fails the build on a forbidden import.

## Consequences

- Rule tests run in milliseconds against in-memory fakes.
- Swapping the Dart toolchain mechanism touches one directory.
- More interfaces than a small CLI strictly needs. The cost is accepted because the two volatile dependencies are real, not hypothetical.

## Alternatives rejected

- **Layered without ports (checks call git directly):** every rule test needs a repository; ADR-0008 becomes a rewrite.
- **A DI container:** hides wiring and adds a dependency for something a 100-line file does.

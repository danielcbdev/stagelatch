# ADR-0013: Checks consume facts, not ASTs

- Status: Accepted
- Date: 2026-11-11

## Context

`codegen/stale`, `tests/solo`, `tests/new-skip` and the import graph need syntactic knowledge of Dart files. Handing checks an analyzer AST would couple rule logic to `package:analyzer`, whose API changes between major versions, and would contradict the rule that checks do not know the analyzer.

## Decision

- Checks receive `DartFileFacts`, a small immutable value produced by the toolchain adapter:
  - `directives`: kind (`import`, `export`, `part`, `partOf`), URI string, location.
  - `annotatedDeclarations`: name, annotation names, a hash of the declaration's tokens, location.
  - `testCalls`: function name, description, enclosing group descriptions, whether `solo` and `skip` are set, location.
- The token hash ignores whitespace and comments, so reformatting a declaration does not change it.
- Facts are purely syntactic: no resolution, no types, no SDK needed to produce them.
- A new rule that needs a new fact adds a field to `DartFileFacts`; it never reaches around the port.

## Consequences

- Rule tests build facts by hand.
- Facts are cacheable by blob id, since they depend only on file content and the extractor version.
- Semantic questions (resolved types, inherited annotations) cannot be answered by facts. Rules that need them go through `DartToolchain.diagnose` or are out of scope.

## Alternatives rejected

- **Expose the AST through the port:** leaks the analyzer into every check.
- **Regular expressions over source:** wrong on comments, strings and multi-line calls.

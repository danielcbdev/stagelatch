# ADR-0017: A hand-written lexer extracts declaration and test-call facts

- Status: Accepted
- Date: 2026-11-20 ([`spike/facts-report.md`](../spike/facts-report.md))

## Context

ADR-0008 and the spike report left one decision to plan 03: the directive scanner of `0.1.0` reads only the top of a file, and `0.2.0` needs more from the same files.

- `codegen/stale` needs `annotatedDeclarations`: name, annotation names, and a SHA-256 of the declaration's tokens.
- `tests/solo` and `tests/new-skip` need `testCalls`: function, description, enclosing groups, `solo` and `skip` arguments, `@Skip`.
- `l10n/unused-key` (`0.3.0`) needs `identifiers`.
- `specs/dart-toolchain.md` section 6 left open whether the facts of a file with a syntax error are null.

ADR-0008 says that adding `package:analyzer` for this needs an ADR. Two candidates were built and measured on the 2,462 Dart files of the spike corpus (report: [`spike/facts-report.md`](../spike/facts-report.md)):

- **S**, a hand-written lexer and recognizers, no dependency.
- **P**, `package:analyzer`'s `parseString`, restricted to `infrastructure/dart/`. Its implementation lives in `benchmark/` and is the reference S is compared with.

| Criterion | S | P |
|---|---|---|
| Agreement with the reference on the corpus | 0 of 2,462 files differ (2,012 declarations, 11,148 test calls, every identifier set) | reference |
| Edge cases of `specs/rules.md` and the plan's Review Focus | 12 of 12 agree | reference |
| All 2,462 files, JIT | 0.43 s | 2.43 s (5.7x) |
| 10 files of s10, cold | 8.6 ms | 133 ms (15x) |
| Estimated `pre-commit` cost, s3 and s10 | +5 ms, +17 ms | +0.16 s, +0.34 s (s10 about 1.3 s) |
| 1 MiB hostile input, twelve shapes | 5 to 117 ms each | stack overflow on two, no answer in 120 s on three, 31 s and 7.4 s on two more |
| Mutated files (1,558) | never threw; lexical check flags 98.1% of the files with parser errors | not applicable |
| Valid files the extractor calls broken | 0 | 30 (generated `*.freezed.dart`, newer syntax than `analyzer` 14.7.0 parses) |
| Dependency | none | `analyzer` and its graph, in the activated tool; 36.8 MB against 8.7 MB of kernel; about 0.08 s more start-up |
| Code | about 940 lines (prototype) | about 270 lines |

Both fit the `pre-commit` budget of 2 s. The decision is made on correctness under hostile input, coupling and cost, in the order of the criteria set for this ADR.

## Decision

1. **The extractor is S: one lexing pass and recognizers over its tokens**, in `lib/src/infrastructure/dart/`, extending `SyntacticFacts`. `package:analyzer` and `package:dart_style` stay out of the tool's dependencies (ADR-0004, ADR-0008). The SDK floor stays `^3.13.0`.
   - The lexer follows the Dart scanner for what the facts depend on: strings (raw, multi-line, nested interpolation through an explicit stack), nested block comments, numbers with digit separators, longest-match operators, and `[]` and `[]=` as single tokens. The hash is defined on its lexemes.
   - It uses no recursion on the input and every loop advances, so the cost is linear in the length of the source (security S6). Each hostile-input shape of the report becomes a test.
2. **SHA-256 is written in `domain`** as a pure function over a string, with the standard vectors and the padding boundaries as tests, and is used for the token hash here and for the baseline fingerprint in plan 03 Task 7. `package:crypto` would be a runtime dependency for 77 lines.
3. **A file that does not lex has no declarations and no calls.** Facts are not null for a text file. `DartFileFacts` gains `isWellFormed`: false when the lexer finds an unterminated string or block comment, or brackets that do not pair. Then `directives` keep their `0.1.0` meaning (read from the top, never failing), and `annotatedDeclarations` and `testCalls` are empty. A check that depends on declarations or calls skips such a file and leaves it to `analyze`; `isWellFormed` is the signal, never an empty list. Other syntax errors are not detected: the facts are best-effort, and `analyze` (pre-push and CI) reports the error.
   - The lexical check flagged 98.1% of the files the parser reports as broken in the fuzz run, and none of the 2,462 valid files. Reporting a null for every parser error would have dropped 30 valid files of the corpus.
4. **`tests.functions` reaches the extractor at construction**, as a constructor argument of `SyntacticFacts`, passed by `DartToolchainFactory.create` from the resolved configuration when the pipeline first touches `context.dart`. No new port. The function that opens a group is the one named `group`; the cache key of facts by blob id includes the set.
5. **`identifiers` come from the same token list**: every identifier and keyword token. The field stays empty until `0.3.0`, when `l10n/unused-key` reads it; a field nobody reads only makes the cache larger. The corpus comparison already agrees on it for every file.
6. **How agreement is kept.**
   - The comparison with `parseString` stays in `benchmark/bin/facts.dart` (`compare`, `edges`, `fuzz`, `adversarial`), run by hand against the corpus; it is not in CI because it needs the corpus.
   - In the repository, unit tests carry hand-written expectations for the edge cases, the adversarial inputs (bounded time, no stack overflow) and a never-throws property over truncations.
   - When Tasks 5 and 6 of plan 03 move the prototype into `lib/`, `benchmark/` depends on it by path, so the comparison runs against the shipped code.
   - A new Dart SDK or language version is a reason to re-run `compare`; a disagreement is a bug of S.

## Consequences

- No new runtime dependency, no version coupling to an `analyzer` release, and the tool's start-up does not grow.
- The tool owns a lexer and a set of recognizers. New operator or literal syntax is a lexer change (digit separators were one during the spike), and new declaration syntax is a recognizer change. Neither can make the gate pass a file `analyze` rejects, because `analyze` is the authority on validity.
- The recognizers are heuristics where a parser has an answer: where a declaration ends, and whether `name(` is a call. The cases known to be wrong are listed in [`spike/facts-report.md`](../spike/facts-report.md) (an initializer list ending in an identifier followed by a map literal body, calls with explicit type arguments, primary-constructor class headers). They are documented limits, not silent ones.
- `DartFileFacts.isWellFormed` is a new field in the port, and checks that read declarations or calls must honor it.
- Facts stay cacheable by blob id (ADR-0013); the key also covers the configured test functions.
- Parada 1 of the `0.2.0` handoff was not needed: S passed every criterion, and no dependency was added.

## Alternatives rejected

- **P, `parseString` in `infrastructure/dart/`.** Less code, and exact grammar. Rejected for the cost it adds: it hangs or overflows the stack on hostile input that a hook must survive (a guard in front of it would be code of ours anyway); it fails on 1.2% of the valid corpus because the embedded `analyzer` is older than the project's language version; it puts `analyzer` into the activated tool and takes 15 times longer on the 10 files of a commit. ADR-0008 already rejected the embedded analyzer for diagnostics.
- **S first, P to confirm.** Two implementations to keep equal, and the dependency anyway.
- **Regular expressions over source.** Rejected by ADR-0013: wrong on comments, strings and multi-line calls.
- **`package:crypto` for SHA-256.** A runtime dependency for a function of 77 lines that has public test vectors.
- **Null facts for a file with a syntax error.** Cannot be implemented without a parser, and would also have to drop the directives that the import graph reads from broken files in `0.1.0`.

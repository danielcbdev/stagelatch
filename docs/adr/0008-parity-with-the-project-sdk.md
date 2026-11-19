# ADR-0008: Parity with the project SDK

- Status: Accepted
- Date: 2026-11-11; mechanism selected 2026-11-19 after the spike ([`spike/report.md`](../spike/report.md))

## Context

The tool runs on the Dart found on PATH. The project may pin another SDK, typically through FVM. Formatter output and diagnostics change between SDK releases. If the gate disagrees with the IDE and with `dart format`, developers lose trust in it.

Facts measured on 2026-11-11: `analyzer` 14.7.0 requires Dart `^3.13.0`; `dart_style` 3.1.14 requires `^3.11.0`. Embedding them ties the tool to one SDK generation.

The spike (plan 00) measured two candidates on a public Flutter app of 2,435 Dart files (Hash-Studios/Prism, Flutter 3.47.8), on a 3-file and a 10-file commit, through the real distribution path (`pub global activate`), and compared each with the SDK's own `dart analyze` and `dart format` on Flutter 3.47.8 and 3.44.9:

| Candidate | Parity (G1: zero differences) | Warm p50, whole process, 10 files (G2: <= 2.0 s) |
|---|---|---|
| A, embedded `package:analyzer` 14.7.0 + `dart_style` 3.1.14 | fails: every lint is missing, because the pub.dev `analyzer` ships no lint rules | 2.69 s |
| B, the resolved SDK's analysis server | passes: 0 differences on both scenarios and both SDKs | 13.60 s |

B's cost is the server linking the package's dependencies on every start (about 13 s on this app, 5 s on a 16-file Flutter package, 1 s on a Dart-only package), and a warm cache does not remove it. A daemon that keeps the server alive was evaluated: about 2.5 s per run on this app with 3 GB of resident memory, and it would need a local socket that security rule S7 forbids.

The resolved SDK's `dart format --stdin-name=<path>` reads the snapshot content from stdin, takes `page_width` from the configuration found for that path, and matched `dart format` byte for byte at about 20 ms per file. Formatting does not need the server.

## Decision

- `format` and `analyze` must produce the same result as `dart format` and `dart analyze` of the SDK the project uses. A difference is a bug.
- SDK resolution order: `sdk_path` in config, then FVM (`.fvm/flutter_sdk`, `.fvmrc`), then `dart` on PATH. The resolved SDK must be outside the repository working tree (see [`security.md`](../engineering/security.md)).
- Analyzer plugins and `custom_lint` are not guaranteed to run. This is a documented limitation.
- **The mechanism is B, delegated, one shot per run**, behind the `DartToolchain` port:
  - **Diagnostics:** one analysis server of the resolved SDK per run (`dart language-server --protocol=analyzer`), with `analysis.setAnalysisRoots` on the affected packages, `analysis.updateContent` for the overlays, and `analysis.getErrors` for the requested files. The server is shut down when the run ends.
  - **Formatting:** the resolved SDK's `dart format --output=show --stdin-name=<path>`, one process per file, with the snapshot content on stdin. The server is not started for formatting.
- **Facts** (ADR-0013) for the import graph come from a hand-written directive scanner in `infrastructure/dart/`. It was about 170 times faster than `parseString` on the corpus and agreed with it on every file.
- **Default hook lists.** `analyze` runs on `pre-push` and `ci` by default, not on `pre-commit`, so the commit hook stays within its 1 to 2 s budget. A team may still list it under `pre-commit`.
- **Dependencies.** The tool takes no dependency on `analyzer` or `dart_style`. Its own SDK floor stays `^3.13.0`; the project's SDK can be any version whose analysis server speaks the legacy protocol, which the parity test runs on Flutter 3.47.8 and 3.44.9.

## Consequences

- No code outside `infrastructure/dart/` may reference the analysis server protocol or spawn `dart format`.
- Parity is exact by construction: the diagnostics and the formatted text come from the project's own SDK.
- `analyze` costs one server start per run: about 1 s on a Dart-only package and seconds to tens of seconds on a large Flutter app. The time budget reports it (ADR-0003); it is never shortened.
- A daemon remains possible later, behind the same port, if real use asks for it. It would need its own ADR, an amendment to S7 and a test that its results equal the one-shot results.
- `annotatedDeclarations` and `testCalls` (`0.2.0`) need more than directives. Plan 03 decides between a larger scanner and a parser; adding `analyzer` for that needs an ADR.

## Alternatives rejected

- **Shell out to `dart analyze` and `dart format` on disk:** cannot see the index (ADR-0001). `dart format --stdin-name` is different: it reads the snapshot content from stdin.
- **A, embedded:** fails parity on every lint, and ties the tool's SDK floor to the `analyzer` release.
- **B with a daemon before `0.1.0`:** about 2.5 s per run on a large app, 3 GB of memory, a local socket, and a lifecycle to maintain, for a gain that still misses the 2 s target.

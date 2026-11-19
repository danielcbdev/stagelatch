# Dart toolchain specification

Status: **Approved (2026-11-12); mechanism selected 2026-11-19 (ADR-0008).** Sections 4 and 5 describe a contract; section 8 records the mechanism that fulfils it. Sections 1–3, 6 and 7 do not depend on the mechanism.

## 1. SDK resolution

`SdkLocator.locate()` returns `ResolvedSdk { root, dartExecutable, flutterExecutable?, version, source }`. First match wins:

| Order | Source | Rule |
|---|---|---|
| 1 | `sdk_path` | Relative paths resolve against the repository root |
| 2 | `fvm` | The directory `.fvm/flutter_sdk` when present; else `.fvmrc` (JSON, key `flutter`) resolved under `$FVM_CACHE_PATH/versions/<v>`, defaulting to `~/fvm/versions/<v>` |
| 3 | `path` | The first `dart` executable on `PATH` |

- A directory is a **Flutter SDK root** when it contains `bin/cache/dart-sdk/version`; the Dart SDK is then `bin/cache/dart-sdk`. It is a **Dart SDK root** when it contains `version` and `bin/dart` (`bin/dart.exe` on Windows).
- For source `path`, symlinks are resolved and the SDK root is found by walking up from the executable until one of the two shapes matches.
- `version` is the first whitespace-delimited token of the SDK's `version` file.
- **Containment (S2):** after resolving symlinks, the SDK root must not be inside the repository work tree. Otherwise: `ConfigException("The Dart SDK must be outside the repository: <path>.")`.
- A configured source that does not resolve is a `ConfigException` naming what was tried: `sdk_path "<value>" is not a Dart or Flutter SDK.`, or `.fvmrc requests Flutter <v>, which is not installed at <path>.` Nothing found at all: `No Dart SDK found. Install Dart or set sdk_path.`

## 2. Packages

`PackageMap` is built from the snapshot: every `pubspec.yaml` defines a package rooted at its directory.

- A file belongs to the package with the deepest root that contains it. Files outside every package belong to none and are skipped by Dart rules.
- `DartPackage { root, name, usesFlutter }`; `usesFlutter` is true when the pubspec has a dependency with `sdk: flutter`.
- Pub workspaces (a root pubspec with `workspace:` and members with `resolution: workspace`) are recognized from `0.3.0`: members share the root's `pubspec.lock` and `.dart_tool/package_config.json`.

**Package config.** Dart analysis needs `.dart_tool/package_config.json` in the working tree for each package that has files to analyze (for workspace members, the root's). When it is missing: usage error `Missing <path>. Run: dart pub get`, where `<path>` is the repository-relative location of the file, for example `.dart_tool/package_config.json` or `packages/ui/.dart_tool/package_config.json`. Checks that do not use diagnostics are unaffected.

## 3. Import graph

Built in `0.1.0` for `analyze.scope: affected`, reused by `tests/affected` and `why`.

- Nodes are the `.dart` files of the snapshot. Edges come from `import`, `export` and `part` directives of each file's facts; `part of` adds the reverse edge.
- URI resolution: relative URIs against the file's directory; `package:<name>/<rest>` to `<package root>/lib/<rest>` when `<name>` is a package of this repository. Other `package:` URIs and all `dart:` URIs are external and ignored.
- Conditional imports contribute every branch.
- An edge is kept even when its target is absent from the snapshot, so the importers of a deleted file can still be found.
- `ImportGraph.dependentsOf(Set<RepoPath>) -> Set<RepoPath>`: the transitive reverse closure, including the inputs, sorted.
- `ImportGraph.shortestChain(RepoPath from, RepoPath to) -> List<RepoPath>?`: breadth-first, ties broken by path order, so the result is deterministic.
- From `0.3.0`, per-file directives are cached by blob id.

## 4. Diagnostics

`DartToolchain.diagnose(Set<RepoPath> files) -> Future<List<DartDiagnostic>>`

- The toolchain analyzes a **materialized snapshot** (ADR-0001): a directory created with `Directory.systemTemp.createTemp('stagelatch-')` (security S10) that holds every regular or executable file of the snapshot whose extension is `.dart`, `.yaml` or `.yml`, written byte for byte from its blob, at its repository-relative path. Symlinks and gitlinks are not written. A path that is absent from the snapshot is absent from the directory, whatever the working tree holds.
- For each package that owns a requested file, the working tree's `.dart_tool/package_config.json` is copied to the same relative place in the directory, with every `rootUri` rewritten: a relative URI whose target is inside the repository stays relative, so it points into the directory; any other becomes the absolute `file:` URI of its original target. Missing file: the usage error of section 2.
- The result contains the diagnostics of exactly the requested files, as the resolved SDK's `dart analyze` would report them on a working tree identical to the snapshot: same codes, messages, severities and ranges, with `analysis_options.yaml` and `// ignore:` applied.
- `DartDiagnostic { location, code, severity (error | warning | info), message, correction? }`, sorted by path, then position, then code.
- The directory is written once, on the first `diagnose`, from the snapshot the toolchain was created with, and removed by `close()`.
- Paths in the result are repository-relative. In a message, every occurrence of the directory's absolute path is replaced by the repository root's, so the message reads as `dart analyze` in the working tree would print it.

## 5. Formatting

`DartToolchain.format(RepoPath path, String source) -> Future<FormatOutcome>`

- `Formatted(text)` holds what the resolved SDK's `dart format` would write for that file; `text == source` means already formatted. `Unparseable()` when the source does not parse.
- Settings come from the snapshot, as `dart format` reads them from disk: the nearest `analysis_options.yaml` (`formatter: page_width`, `formatter: trailing_commas`), and the file's language version (a `// @dart=` comment, else the package's SDK constraint).
- The line ending of the output is the line ending of the first line of the input.

## 6. Facts

`DartToolchain.facts(SnapshotFiles files, RepoPath path) -> Future<DartFileFacts?>`, purely syntactic (ADR-0013). Null when the file is absent or has syntax errors.

```dart
enum DirectiveKind { import, export, part, partOf }

final class Directive {
  DirectiveKind get kind;
  String get uri;                       // as written; conditional branches produce one Directive each
  Location get location;
}

final class AnnotatedDeclaration {
  String get name;                      // 'Order', or 'Order.fromJson' for members
  List<String> get annotations;         // names as written, without '@' or arguments, sorted
  String get tokenHash;                 // SHA-256 hex of the declaration's tokens joined by one space
  Location get location;
}

final class TestCall {
  String get function;                  // 'test', 'group', ...
  String get description;               // literal value, or source text when not a literal
  List<String> get groups;              // enclosing group descriptions, outermost first
  Location? get solo;                   // location of a `solo` argument that is not literal false
  Location? get skip;                   // location of a `skip` argument (not false/null) or @Skip
  Location get location;
}

final class DartFileFacts {
  List<Directive> get directives;
  List<AnnotatedDeclaration> get annotatedDeclarations;
  List<TestCall> get testCalls;
  Set<String> get identifiers;          // every identifier token; used by l10n/unused-key
}
```

- `annotatedDeclarations` covers top-level declarations and class members that carry at least one annotation other than `override`, `protected`, `visibleForTesting`, `immutable`, `Deprecated` and `deprecated`.
- Tokens exclude comments and whitespace, so formatting never changes `tokenHash`.
- `testCalls` are collected only for calls to functions named in `tests.functions`; the adapter receives that list at construction.
- `identifiers` is filled from `0.3.0`; before that it is empty.

## 7. Lifecycle and cost

- `DartToolchainFactory.create(ResolvedSdk, SnapshotFiles, ...) -> DartToolchain` is called by the pipeline the first time a check touches `context.dart`. A run that needs no Dart knowledge never pays for it. Creating starts no process and writes no file.
- A toolchain is bound to one snapshot view. The fix phase and the verify phase each get their own, created on first access, because fixes change the index between them; the pipeline closes both.
- `facts` must not require the expensive part of the toolchain to start: syntactic extraction runs in-process.
- `DartToolchain.close()` is called in a `finally` by the pipeline.

## 8. Mechanism

Selected by the spike ([`spike/report.md`](../spike/report.md)) and recorded in ADR-0008: the resolved SDK does the work, one shot per run.

| | How |
|---|---|
| Diagnostics (section 4) | On the first `diagnose`, write the materialized snapshot (section 4), then start one `dart language-server --protocol=analyzer` of the resolved SDK: `server.setSubscriptions` with `STATUS`; `analysis.setAnalysisRoots` with the materialized roots of the packages that own the requested files; then `analysis.getErrors` for each requested file. No `analysis.updateContent`. `close()` sends `server.shutdown`, kills the process if it has not exited after 5 s, then removes the directory. Writing the corpus's 2,472 Dart and YAML files took about 0.25 s. |
| Formatting (section 5) | `dart format --output=show --stdin-name=<absolute path>` of the resolved SDK, the snapshot content on stdin. Exit 0: stdout is the formatted text. Exit 65 (the source does not parse): `Unparseable()`. Any other exit is an internal error naming the exit code. No server. |
| Facts (section 6) | A hand-written directive scanner, in-process. It skips comments and strings and yields `import`, `export`, `part` and `part of` with their URIs, conditional branches included. |
| Parity | By construction: the project's own SDK produces every diagnostic and every formatted text. |
| Cost | Formatting: about 20 ms per file. Diagnostics: one server start, about 1 s on a Dart-only package, about 5 s on a small Flutter package, about 13 s on a 2,400-file Flutter app, cache or not. |
| Coupling | The analysis server's legacy protocol, tested on Flutter 3.47.8 and 3.44.9. No `analyzer` or `dart_style` dependency. |

The candidates that were measured and rejected (embedded `analyzer` with `OverlayResourceProvider`, and a long-lived server) are described in the spike report.

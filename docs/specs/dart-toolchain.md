# Dart toolchain specification

Status: **Approved (2026-11-12).** Sections 4 and 5 describe a contract; which mechanism fulfils it is decided by the spike (ADR-0008). Sections 1–3, 6 and 7 do not depend on that decision.

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

- The toolchain analyzes the working tree **with overlays**: every path in `GitRepository.divergingFromWorktree(snapshot)` is shown with its snapshot content; a path that is absent from the snapshot is shown as deleted.
- The result contains the diagnostics of exactly the requested files, as the resolved SDK's `dart analyze` would report them on a working tree identical to the snapshot: same codes, messages, severities and ranges, with `analysis_options.yaml` and `// ignore:` applied.
- `DartDiagnostic { location, code, severity (error | warning | info), message, correction? }`, sorted by path, then position, then code.
- Overlays are installed once, before the first request, and never change during a run.

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

- `DartToolchainFactory.create(ResolvedSdk, overlays) -> DartToolchain` is called by the pipeline the first time a check touches `context.dart`. A run that needs no Dart knowledge never pays for it.
- `facts` must not require the expensive part of the toolchain to start: syntactic extraction runs in-process.
- `DartToolchain.close()` is called in a `finally` by the pipeline.

## 8. The two candidate mechanisms

Both implement sections 4 and 5 behind the same port. The spike measures both; see [`plans/00-spike.md`](../plans/00-spike.md).

| | A, embedded | B, delegated |
|---|---|---|
| Diagnostics | `package:analyzer`: `AnalysisContextCollection` with an `OverlayResourceProvider`, `sdkPath` set to the resolved SDK | The resolved SDK's `dart language-server --protocol=analyzer`: `analysis.setAnalysisRoots`, `analysis.updateContent`, `analysis.getErrors` |
| Formatting | `package:dart_style` | The same server: `edit.format` |
| Parity | Depends on how close the embedded versions are to the project's SDK | By construction |
| Cost | No spawn; analyzer warm-up inside the tool's JIT | One process spawn; the server's own startup |
| Coupling | Tool's SDK floor follows `analyzer` (14.7.0 needs Dart 3.13) | Protocol only |

Whichever is chosen, syntactic facts need a Dart parser in-process. The spike also decides between `package:analyzer`'s `parseString` (stable API, wide version range) and a hand-written directive scanner for the import graph alone.

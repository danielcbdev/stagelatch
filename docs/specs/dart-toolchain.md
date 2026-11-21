# Dart toolchain specification

Status: **Approved (2026-11-12); mechanism selected 2026-11-19 (ADR-0008).** Sections 4 and 5 describe a contract; section 8 records the mechanism that fulfils it. Sections 1–3, 6 and 7 do not depend on the mechanism.

## 1. SDK resolution

`SdkLocator.locate()` returns `ResolvedSdk { root, dartExecutable, flutterExecutable?, version, source }`. First match wins:

| Order | Source | Rule |
|---|---|---|
| 1 | `sdk_path` | Relative paths resolve against the repository root |
| 2 | `fvm` | The directory `.fvm/flutter_sdk` when present; else `.fvmrc` (JSON, key `flutter`) resolved under `$FVM_CACHE_PATH/versions/<v>`, defaulting to `~/fvm/versions/<v>` |
| 3 | `path` | The first `dart` executable on `PATH`; on Windows `dart.exe` or `dart.bat`, the name a Flutter SDK puts on `PATH` |

- A directory is a **Flutter SDK root** when it contains `bin/cache/dart-sdk/version`; the Dart SDK is then `bin/cache/dart-sdk`. It is a **Dart SDK root** when it contains `version` and `bin/dart` (`bin/dart.exe` on Windows).
- For source `path`, symlinks are resolved and the SDK root is found by walking up from the executable until one of the two shapes matches.
- `version` is the first whitespace-delimited token of the SDK's `version` file.
- **Containment (S2):** after resolving symlinks, the SDK root must not be inside the repository work tree. Otherwise: `ConfigException("The Dart SDK must be outside the repository: <path>.")`.
- A configured source that does not resolve is a `ConfigException` naming what was tried: `sdk_path "<value>" is not a Dart or Flutter SDK.`, or `.fvmrc requests Flutter <v>, which is not installed at <path>.` Nothing found at all: `No Dart SDK found. Install Dart or set sdk_path.`

## 2. Packages

`PackageMap` is built from the snapshot: every `pubspec.yaml` defines a package rooted at its directory.

- A file belongs to the package with the deepest root that contains it. Files outside every package belong to none and are skipped by Dart rules.
- `DartPackage { root, name, usesFlutter }`; `usesFlutter` is true when the pubspec has a dependency with `sdk: flutter`.
- A `pubspec.yaml` that does not parse, or has no string `name`, still defines a package. Its name is the empty string, so no `package:` URI resolves to it. The directory name is not used: it depends on where the repository was cloned (ADR-0003).
- **Pub workspaces** are recognized from `0.3.0`. A root pubspec lists its members under `workspace:`, each entry a directory or, from language version 3.11, a glob; a member has `resolution: workspace`. The members of a root are the packages whose directory matches one of its entries (globs are matched against the directories of the snapshot's packages) and that declare `resolution: workspace`. A member belongs to the nearest enclosing package that lists it; a package that declares `resolution: workspace` and that no enclosing package lists belongs to none and resolves on its own.
- `PackageMap.resolutionRootOf(DartPackage) -> RepoPath?` is the directory that holds the package's `pubspec.lock` and `.dart_tool/package_config.json`: the workspace root's directory for a member (null for the repository root, as for `DartPackage.root`), the package's own directory otherwise. Verified with Dart 3.13.4: after `pub get` a member has no `package_config.json` and no lock of its own; the root's config lists every member with a relative `rootUri`, and `dart test` run in a member's directory resolves through it.

**Package config.** Dart analysis needs `.dart_tool/package_config.json` in the working tree for each package that has files to analyze, found at the package's resolution root (for a workspace member, the workspace root's). Packages that share a resolution root share one copy. When it is missing: usage error `Missing <path>. Run: dart pub get`, where `<path>` is the repository-relative location of the file, for example `.dart_tool/package_config.json` or `packages/ui/.dart_tool/package_config.json`. Checks that do not use diagnostics are unaffected.

## 3. Import graph

Built in `0.1.0` for `analyze.scope: affected`, reused by `tests/affected` and `why`.

- Nodes are the `.dart` files of the snapshot. Edges come from `import`, `export` and `part` directives of each file's facts; `part of` adds the reverse edge.
- URI resolution: relative URIs against the file's directory; `package:<name>/<rest>` to `<package root>/lib/<rest>` when `<name>` is a package of this repository. Other `package:` URIs and all `dart:` URIs are external and ignored.
- Conditional imports contribute every branch.
- An edge is kept even when its target is absent from the snapshot, so the importers of a deleted file can still be found.
- `ImportGraph.dependentsOf(Set<RepoPath>) -> Set<RepoPath>`: the transitive reverse closure, including the inputs, sorted.
- `ImportGraph.shortestChain(RepoPath from, RepoPath to) -> List<RepoPath>?`: breadth-first, ties broken by path order, so the result is deterministic.
- `ImportGraph.dependenciesOf(Set<RepoPath>) -> Set<RepoPath>`: the transitive forward closure, including the inputs, sorted. Edges to targets that are absent from the snapshot are followed, so the closure holds those targets (they have no further edges). `tests/affected` uses it for the divergence test ([ADR-0018](../adr/0018-affected-tests-run-against-validated-snapshot.md)).
- `ImportGraph.directiveOf(RepoPath importer, RepoPath target) -> Location?`: the location of the first directive of `importer`, in source order, that resolves to `target`; null when there is none. Used to place the skip warning of `tests/affected`.
- From `0.3.0`, the facts of every file, directives included, are cached by blob id ([section 6.1](#61-the-facts-cache)).

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

`DartToolchain.facts(SnapshotFiles files, RepoPath path) -> Future<DartFileFacts?>`, purely syntactic (ADR-0013). Null when the file is absent or is not text (`SnapshotFiles.readText` is null).

**Directives in `0.1.0`.** Only `directives` is filled, by the directive scanner of section 8. It reads from the top of the file, skipping whitespace, comments, a `#!` line, `library` directives and annotations, and stops at the first token that does not start a directive. Inside a directive, string literals outside parentheses are the URI, and adjacent literals are concatenated; literals inside a configuration's parentheses are not URIs, but the literal after each `if (...)` is a branch. `part of` followed by a library name instead of a string produces nothing. The scanner does not detect syntax errors: a broken file still yields the directives before the point where it stops. The location of a `Directive` is its URI literal, from the opening quote to just after the closing quote (for adjacent literals, from the first opening quote to just after the last closing quote). Whether a file that does not parse still has facts is decided in the next paragraph.

**The extractor from `0.2.0` (ADR-0017).** `annotatedDeclarations`, `testCalls` and `identifiers` come from one hand-written lexer over the whole file and recognizers over its tokens, in-process, with no `analyzer`. The lexer follows the Dart scanner: strings (raw, multi-line, nested interpolation), nested block comments, numbers with digit separators, longest-match operators, and `[]` and `[]=` as single tokens. It uses no recursion on the input and runs in time linear in its length (security S6).

**Facts of a file that does not lex.** Facts are not null for a text file. `isWellFormed` is false when the lexer finds an unterminated string or block comment, or brackets that do not pair. Then `directives` are what the scanner above reads from the top of the file, `annotatedDeclarations` and `testCalls` are empty, and a check that depends on them skips the file and leaves it to `analyze`. A syntax error the lexer cannot see leaves `isWellFormed` true and the facts best-effort; `analyze` reports the error.

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
  bool get isWellFormed;                // false: unterminated string or block comment, or unpaired brackets
}
```

- `annotatedDeclarations` covers top-level declarations and class members that carry at least one annotation other than `override`, `protected`, `visibleForTesting`, `immutable`, `Deprecated` and `deprecated`.
- A member is named `Class.member`; a constructor is `Class.named`, or `Class.new` when it has no name; an enum constant is `Enum.value`; an unnamed extension is `<unnamed>`. A top-level variable declaration is named by its first variable. `annotations` are the annotation names as written (`JsonKey`, `pkg.Annotation`, `Foo.bar`), without type arguments or arguments, sorted.
- The declaration's tokens run from its first `@` to its last token, annotations included. Tokens exclude comments and whitespace, so formatting never changes `tokenHash`. The token stream is the Dart scanner's own (`>>` is one token, `[]` and `[]=` are one token, an interpolated string is split at each `$`), because the hash is defined on it.
- `testCalls` are collected only for calls to functions named in `tests.functions`; the adapter receives that list at construction, through `DartToolchainFactory.create`, and no new port exists for it. A call is unqualified (`test(...)`, not `obj.test(...)` or a cascade) and has at least one positional argument. A group is a call to the function named `group`, and `groups` lists the descriptions of the `group` calls that enclose the call. The description is the first positional argument: a string literal's value (escapes decoded, adjacent literals joined), or the argument's source text otherwise. `skip` is set by the call's own `skip:` argument (other than `false` and `null`), else by a `@Skip` annotation on the enclosing top-level function, else by one on the library; its location is that argument or annotation.
- `identifiers` is filled from `0.3.0`; before that it is empty. It holds every identifier and keyword token of the file, interpolated expressions included, and nothing from comments or string contents. For a file that is not well formed it is empty, like `annotatedDeclarations` and `testCalls`; a rule that reads it must check `isWellFormed` first.

### 6.1 The facts cache

Since `0.3.0`, `DartToolchain.facts` is answered from a content-addressed cache when the file is in the snapshot as a regular or executable file and the cache has an entry for it. A cache hit is indistinguishable from recomputation; any failure of the cache is a miss, never an error.

- **Port.** `Cache { Future<String?> read(String namespace, String key); Future<void> write(String namespace, String key, String value) }` in `application/ports`. No other port is added; the extractor and the codec live in `infrastructure/dart/`.
- **Namespace** `facts-v<factsFormatVersion>`. `factsFormatVersion` is one integer that covers both the encoding of the entry and the behaviour of the extractor (lexer and recognizers). It is raised by any change that can alter the facts of some input, and a golden test over a fixed corpus fails when the facts change without it.
- **Key** `<blob id>-<sha256 of the test functions>`: the blob id as git prints it, a hyphen, and the hexadecimal SHA-256 of the sorted `tests.functions` set joined by `\n` (ADR-0017: the facts depend on that set). The path is not part of the key.
- **Value** a JSON document with a `v` member equal to `factsFormatVersion`. It holds every field of `DartFileFacts` with positions only; the path is attached on read, so the same blob at two paths shares one entry and a hit carries the requested path. `identifiers` are stored sorted. An entry that does not decode, or whose `v` differs, is a miss.
- **Location** `<git common dir>/stagelatch/cache/<namespace>/<first two characters of the key>/<key>`. Linked worktrees share the common directory.
- **Writes** go to a fresh temporary directory next to the target and are renamed into place, so a reader never sees a partial entry. Writers of one key store the same bytes, so a concurrent writer is harmless. Where renaming over an existing file fails (Windows), the write is abandoned silently: the entry is there already. A directory that cannot be created or written makes every write a no-op and every read a miss.
- **Eviction** there is none; the directory is safe to delete at any time.

## 7. Lifecycle and cost

- `DartToolchainFactory.create(ResolvedSdk, SnapshotFiles, ...) -> DartToolchain` is called by the pipeline the first time a check touches `context.dart`. A run that needs no Dart knowledge never pays for it. Creating starts no process and writes no file.
- A toolchain is bound to one snapshot view. The fix phase and the verify phase each get their own, created on first access, because fixes change the index between them; the pipeline closes both.
- `facts` must not require the expensive part of the toolchain to start: syntactic extraction runs in-process. On a cache hit the blob is not even read.
- `DartToolchain.close()` is called in a `finally` by the pipeline.

## 8. Mechanism

Selected by the spike ([`spike/report.md`](../spike/report.md)) and recorded in ADR-0008: the resolved SDK does the work, one shot per run.

| | How |
|---|---|
| Diagnostics (section 4) | On the first `diagnose`, write the materialized snapshot (section 4), then start one `dart language-server --protocol=analyzer` of the resolved SDK: `server.setSubscriptions` with `STATUS`; `analysis.setAnalysisRoots` with the materialized roots of the packages that own the requested files; then `analysis.getErrors` for each requested file. No `analysis.updateContent`. `close()` sends `server.shutdown`, kills the process if it has not exited after 5 s, then removes the directory. Writing the corpus's 2,472 Dart and YAML files took about 0.25 s. |
| Formatting (section 5) | `dart format --output=show --stdin-name=<path>` of the resolved SDK, the source on stdin. `<path>` is the file's place inside a settings directory written on the first `format`: the snapshot's `pubspec.yaml` and `analysis_options.yaml` files and the package configs (rewritten as in section 4), no Dart files. So `page_width`, `trailing_commas` and the language version come from the snapshot, never from the working tree. `close()` removes it. Exit 0: stdout is the formatted text. Exit 65 (the source does not parse): `Unparseable()`. Any other exit is an internal error naming the exit code. No server. |
| Facts (section 6) | A hand-written lexer and recognizers, in-process ([ADR-0017](../adr/0017-hand-written-lexer-for-declaration-and-test-call-facts.md), [`spike/facts-report.md`](../spike/facts-report.md)). The directive scanner of `0.1.0` yields `import`, `export`, `part` and `part of` with their URIs, conditional branches included; from `0.2.0` the lexer also yields annotated declarations and test calls. |
| Parity | By construction: the project's own SDK produces every diagnostic and every formatted text. |
| Cost | Formatting: about 20 ms per file. Diagnostics: one server start, about 1 s on a Dart-only package, about 5 s on a small Flutter package, about 13 s on a 2,400-file Flutter app, cache or not. |
| Coupling | The analysis server's legacy protocol, tested on Flutter 3.47.8 and 3.44.9. No `analyzer` or `dart_style` dependency. |

The candidates that were measured and rejected (embedded `analyzer` with `OverlayResourceProvider`, and a long-lived server) are described in the spike report.

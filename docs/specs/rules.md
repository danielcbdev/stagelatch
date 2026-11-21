# Rule catalog

Status: **Approved (2026-11-12).** Every rule the tool can report, with the exact message. `<x>` marks a substituted value.

## Conventions

- **Changed file** means a path in the changeset that still exists in the snapshot (added, modified, renamed, type-changed).
- **Base** is the other side of the changeset: `HEAD` for pre-commit, the base commit for pre-push and `ci`.
- A check runs only when its **trigger** matches the changeset. A check that does not run costs nothing.
- Locations are 1-based. `file:1:1` is used when a finding concerns a whole file.
- Symlinks, submodule entries, binary files and files above 5 MiB are skipped by every content rule. Path-based rules still see them.
- Default severity is `error` unless stated.

| Check | Rule | Default | Since |
|---|---|---|---|
| `format` | `unformatted` | error | 0.1.0 |
| `analyze` | `<analyzer code>` | by `analyze.fail_on` | 0.1.0 |
| `sensitive-files` | `signing`, `credentials` | error | 0.1.0 |
| `pubspec` | `path-dependency`, `dependency-overrides`, `unparseable` | error | 0.1.0-dev.1 |
| `pubspec` | `unpinned-git`, `build-number-regression`, `lockfile-out-of-sync` | error | 0.2.0 |
| `codegen` | `stale` | error | 0.2.0 |
| `l10n` | `missing-key`, `placeholder-mismatch`, `unparseable` | error | 0.2.0 |
| `l10n` | `unused-key` | warning | 0.3.0 |
| `assets` | `missing`, `undeclared`, `max-file-size` | error | 0.2.0 |
| `tests` | `solo` | error | 0.2.0 |
| `tests` | `new-skip` | warning | 0.2.0 |
| `tests` | `affected` | error | 0.3.0 |
| `stagelatch` | `invalid-ignore` | warning | 0.1.0 |

## `format`

Phase: fix. Trigger: any changed `.dart` file.

### `format/unformatted`

- For each changed `.dart` file, format the snapshot text with the project's formatter settings ([`dart-toolchain.md`](dart-toolchain.md#5-formatting)). A finding exists when the result differs from the input.
- A file that does not parse produces no `format` finding; `analyze` reports the syntax error.
- Location: line and column of the first differing character.
- Message: `File is not formatted.`
- Fix: the formatted text. Applied when the snapshot is the index, `format.fix` is true and `--no-fix` is absent; the finding then becomes an applied fix and does not block.

## `analyze`

Phase: verify. Trigger: any changed `.dart`, `pubspec.yaml` or `analysis_options.yaml` file.

### `analyze/<code>`

- `<code>` is the analyzer's diagnostic code, verbatim, e.g. `analyze/unused_import`.
- Files analyzed, by `analyze.scope`:
  - `changed`: changed `.dart` files.
  - `affected`: changed `.dart` files plus every file of the same repository that imports a changed or deleted `.dart` file, directly or transitively. Deleted files themselves are not analyzed; their importers are.
  - `all`: every `.dart` file of each package that contains a changed file.
  - When `pubspec.yaml` or `analysis_options.yaml` changed, the scope for that package is `all`.
- Severity mapping: an analyzer severity listed in `analyze.fail_on` becomes `error`. Otherwise `ERROR` and `WARNING` become `warning`, and `INFO` is dropped.
- The analyzer's own `// ignore:` comments and `analysis_options.yaml` are honored, as `dart analyze` honors them.
- Message: the analyzer's message, sanitized. Location: the analyzer's range.

## `sensitive-files`

Phase: verify. Trigger: any changed file. Path-based except where noted. Content is never printed.

### `sensitive-files/signing`

- Matches a changed file whose basename is `key.properties`, or whose extension is `.jks`, `.keystore`, `.p8`, `.p12` or `.pfx`.
- Location: `file:1:1`. Message: `Signing material must not be committed.`

### `sensitive-files/credentials`

- Matches a changed file whose basename is `.env` or starts with `.env.`, except `.env.example`, `.env.sample` and `.env.template`.
- Also matches a changed `.json` file of at most 1 MiB whose top-level object has `"type": "service_account"`.
- Location: `file:1:1`. Message: `Credentials file must not be committed.`

## `pubspec`

Phase: verify. Trigger: any changed `pubspec.yaml`, `pubspec.lock` or `pubspec_overrides.yaml`. Each rule looks at every pubspec in the changeset.

### `pubspec/unparseable`

- The changed `pubspec.yaml` is not valid YAML or its root is not a map. The other `pubspec` rules skip that file.
- Location: where the parser failed. Message: `pubspec.yaml is not valid YAML: <reason>.`

### `pubspec/path-dependency`

- For each entry under `dependencies` and `dev_dependencies` that has a `path` key: resolve the path relative to the pubspec's directory. A finding exists when the result leaves the repository, or when `<result>/pubspec.yaml` is not in the snapshot.
- Entries under `dependency_overrides` are left to the next rule.
- Location: the `path` value. Message: `Dependency "<name>" uses a path that is not a package in this repository: <path>.`

### `pubspec/dependency-overrides`

- `dependency_overrides` is present and non-empty. Location: the key. Message: `dependency_overrides must not be committed: <names, comma-separated, sorted>.`
- A changed `pubspec_overrides.yaml`. Location: `file:1:1`. Message: `pubspec_overrides.yaml must not be committed.`

### `pubspec/unpinned-git`

- A dependency with a `git` source and no `ref`. Location: the `git` key. Message: `Git dependency "<name>" has no ref.`
- With `pubspec.require_sha: true`, also a `ref` that is not 40 hexadecimal characters. Location: the `ref` value. Message: `Git dependency "<name>" must be pinned to a full commit SHA, found "<ref>".`

### `pubspec/build-number-regression`

- Applies when the target branch matches a glob in `pubspec.monotonic_build_number`. Target branch: the current branch (pre-commit), the pushed remote branch (pre-push), the `--base` ref (`ci`).
- Compare `version` in the snapshot with `version` in the base. A finding exists when the snapshot's version is lower by pub semantic version ordering, or the versions are equal apart from the build number and the snapshot's build number is lower, or the base had a build number and the snapshot has none.
- Build numbers are compared as integers when both are integers, otherwise as strings.
- Location: the `version` value. Message: `Version went backwards: <base version> -> <snapshot version>.`

### `pubspec/lockfile-out-of-sync`

- Applies to a `pubspec.yaml` that has a sibling `pubspec.lock` in the snapshot.
- For each entry under `dependencies` and `dev_dependencies`:
  - no package of that name in the lock: `"<name>" is missing from pubspec.lock.`
  - hosted dependency whose locked version is not allowed by the constraint: `pubspec.lock does not satisfy "<name>": locked <version>, required <constraint>.`
  - source kind differs (hosted, git, path, sdk): `pubspec.lock resolves "<name>" from <locked source>, but pubspec.yaml declares <declared source>.`
- For each lock entry marked `direct main` or `direct dev` that the pubspec does not declare: `pubspec.lock lists "<name>" as a direct dependency, but pubspec.yaml does not declare it.`
- Location: the dependency's key in `pubspec.yaml`; for the last case, `pubspec.yaml:1:1`.
- A changed `pubspec.lock` triggers the rule for the `pubspec.yaml` beside it even when that file did not change. A lock that is not readable YAML is left to `pub`.
- A dependency that is also under `dependency_overrides` is not compared: the override decides what the lock resolves.
- No version solving is performed and transitive dependencies are not checked.
- **Pub workspaces** ([`dart-toolchain.md`](dart-toolchain.md#2-packages)). The lock of a member is the `pubspec.lock` of its workspace root, which is where `pub get` writes it, and a changed root lock triggers the rule for every pubspec of that workspace. The workspace's own members are not in the lock, so a dependency that names a member is not compared. In a workspace lock only the root pubspec's dependencies are marked `direct main` or `direct dev`; those of the members are `transitive`. The "lists it as a direct dependency" case therefore applies only to the root pubspec, and the other cases apply to each pubspec of the workspace.

## `codegen`

Phase: verify. Trigger: any changed `.dart` file. Disabled when `codegen.generated_files_committed` is false.

### `codegen/stale`

- A **source file** is a changed `.dart` file with at least one `part` directive whose URI ends with a suffix in `codegen.generated_suffixes`.
- For each source file, take the facts of the snapshot version and of the base version ([`dart-toolchain.md`](dart-toolchain.md#6-facts)).
- The file's **codegen signature** is the list of its generated-part URIs plus, for every annotated declaration, its name, annotation names and token hash.
- A finding exists when the signature differs from the base's (or the file is new) **and** the generated part file is not in the changeset.
  - Location: the first annotated declaration whose entry differs; for a new file, the `part` directive.
  - Message: `"<declaration>" changed but <generated file> was not updated in this change.`
- A finding also exists when the generated part file is absent from the snapshot.
  - Location: the `part` directive. Message: `<generated file> is declared as a part but is missing.`
- Whitespace and comment changes do not change a token hash, so they never trigger the rule.
- The base version is read from the base snapshot at the file's previous path when it was renamed. With no base, no such file in the base, or base facts that are not well formed, the file is treated as new.
- Facts that are not well formed ([`dart-toolchain.md`](dart-toolchain.md#6-facts)) leave the file to `analyze`: no finding.
- One finding per generated part that is missing from the changeset. A part that is absent from the snapshot yields only the "missing" finding for that part.
- `<declaration>` is the first differing declaration by name. When a declaration was only removed, its name is used and the location is the first `part` directive; when only the list of parts differs, `<declaration>` is the file's name and the location is the `part` directive.

## `l10n`

Phase: verify. Trigger: a changed `l10n.yaml` or `.arb` file; `unused-key` also triggers on any `.dart` file that was added, modified, deleted or renamed (either path), and then looks at the package that owns it.

Setup, per package with an `l10n.yaml`: `arb-dir` (default `lib/l10n`) and `template-arb-file` (default `app_en.arb`), both read relative to the package. A package without `l10n.yaml`, with one that is not a YAML map, or whose `arb-dir` is absolute or leaves the package, is skipped; an empty `l10n.yaml` means the defaults. Keys starting with `@` are metadata and are not message keys. The **ARB files** of a package are the `.arb` files directly inside `arb-dir`. A package is looked at when its `l10n.yaml` changed, or an ARB file of its directory changed or was deleted; every locale is then compared with the template, so adding a key to the template flags every translation that lacks it. A template that is missing or not a JSON object skips every comparison.

### `l10n/unparseable`

- A changed `.arb` file in the ARB directory is not valid JSON or its root is not an object. Location: where the parser failed, or the whole file for a root that is not an object (reason `expected an object at the top level`). Message: `<file> is not valid JSON: <reason>.` `<file>` is the file name. A file that is not valid is left out of the other rules; one that did not change is not reported.

### `l10n/missing-key`

- A message key of the template that is absent from another `.arb` file of the ARB directory.
- Location: the key in the template. Message: `Key "<key>" is missing in <file>.`

### `l10n/placeholder-mismatch`

- For a key present in both the template and a translation, when both values are strings: the set of ICU argument names in the two messages differs. Argument names are collected from `{name}`, `{name, plural, ...}`, `{name, select, ...}` and nested messages; quoted text (`'{'`) is skipped.
- Location: the key in the translation. Message: `Placeholders of "<key>" differ from the template: expected {<sorted names>}, found {<sorted names>}.`

### `l10n/unused-key`

- A template key whose name is not in the `identifiers` ([`dart-toolchain.md`](dart-toolchain.md#6-facts)) of any non-generated `.dart` file of the package. Generated files are those under the l10n output directory and those matching `codegen.generated_suffixes`. "Of the package" means `PackageMap.packageOf` returns that package, so a nested package's files do not count.
- `identifiers` holds every identifier and keyword token of a file and nothing from comments or string contents: `l10n.checkoutTitle`, `AppLocalizations.of(context).checkoutTitle`, `'${l10n.checkoutTitle}'` and `'$checkoutTitle'` all count as a use of `checkoutTitle`.
- A package with a scanned file whose facts are not well formed produces no `unused-key` finding: such a file has no identifiers, and an empty set must not be read as "no uses". Its syntax error is left to `analyze`.
- This rule scans the whole package; it is the only rule that is not change-aware. It is looked at when `l10n.yaml` or an ARB file of the package changed, or a `.dart` file of the package changed.
- Location: the key in the template. Message: `Key "<key>" is not referenced by any Dart file.`

## `assets`

Phase: verify. Trigger: a changed `pubspec.yaml`, or a changed or deleted file under a directory of `assets.roots`. Paths matching `assets.ignore` are exempt. `assets.roots`, `assets.ignore` and the paths of declarations are all relative to the package that owns the `pubspec.yaml`, so a package at `packages/ui` has its roots at `packages/ui/assets`. The pubspec of a package is examined when it changed or when an asset of its package changed or was deleted; every declaration of an examined pubspec is checked for `missing`, and every changed file under a root is checked for `undeclared` and `max-file-size`.

A file is **declared** when the `flutter: assets:` list of its package's pubspec contains its exact path, or its directory followed by `/`, or the directory one level up when the file sits in a resolution variant directory (a directory named like `2.0x`). Directory entries are not recursive, as in Flutter. Font files listed under `flutter: fonts:` are declared.

### `assets/missing`

- A declared file path that is not in the snapshot (a font under `flutter: fonts:` included), or a declared directory with no file in the snapshot. A directory counts as having a file when a file is directly inside it or directly inside one of its resolution variant directories (`2.0x`).
- Location: the entry in `pubspec.yaml`. Message: `Asset "<entry>" is declared but does not exist.`

### `assets/undeclared`

- A changed file under an asset root that is not declared.
- Location: `file:1:1`. Message: `File is under "<root>" but is not declared in pubspec.yaml.` `<root>` is the root as configured, with a trailing slash. Symlinks and submodule entries are not assets.

### `assets/max-file-size`

- A changed file under an asset root whose blob is larger than `assets.max_file_size`.
- Location: `file:1:1`. Message: `File is <size>, larger than the limit of <limit>.` Sizes are printed with one decimal and the unit of the limit (binary: 1KB is 1024 bytes); the limit itself is printed in its own unit without a decimal when it is a whole number of it, as in `500KB`.

## `tests`

A **test file** is a `.dart` file under a package's `test/` directory, at any depth, whose name ends with `_test.dart`. A **test call** is a call to a function named in `tests.functions`. Its **key** is the list of enclosing group descriptions followed by its own description; calls whose description is not a string literal use the source text of the argument. A group is a call to `group`, and a `group` call is itself a test call, so `group('x', ..., skip: true)` skips "x". A file whose facts are not well formed is left to `analyze`.

### `tests/solo`

Phase: verify. Trigger: a changed test file.

- A test call with a `solo` argument that is not the literal `false`.
- Location: the `solo` argument. Message: `"solo" must not be committed: it silently skips every other test.`

### `tests/new-skip`

Phase: verify. Trigger: a changed test file.

- A test call with a `skip` argument that is not the literal `false` or `null`, or carrying a `@Skip` annotation, whose key has no skipped counterpart in the base version of the file. Skips that already existed in the base are not reported: for each key the skipped calls of the snapshot are counted against the skipped calls of the base version (at the file's previous path when renamed; with no base, every skip is new), and when the snapshot has more, the later ones in source order are reported. A `@Skip` annotation on the library or on the enclosing function makes each call under it skipped.
- Location: the `skip` argument or annotation. Message: `Test "<description>" was skipped in this change.`

### `tests/affected`

Phase: verify. Trigger: any changed `.dart` file, or a change to `pubspec.yaml`, `pubspec.lock` (when present in the snapshot) or `analysis_options.yaml` of a package. Entry points: pre-push and `ci` only (never pre-commit).

- **Affected test files:** changed test files, plus test files that import a changed or deleted file directly or transitively; a change to `pubspec.yaml`, `analysis_options.yaml`, or a committed `pubspec.lock` of a package selects all tests of that package. A workspace root `pubspec.yaml` (and root lock when in the snapshot) selects all tests of every workspace member.
- **Closure:** the affected test files; every file in their transitive import closure (`import`/`export`/`part`, including edges to absent targets); and for each package that owns an affected test, its `pubspec.yaml`, `analysis_options.yaml`, and `pubspec.lock` when that lock exists in the snapshot. For workspace members, the workspace root `pubspec.yaml` and root lock (when in the snapshot) are in the closure too.
- **Dirty closure:** a path of the closure is divergent when (a) it differs between the snapshot and the working tree, (b) it is the target of an import edge of the closure, is absent from the snapshot, a regular file exists at that path on disk and `git check-ignore` does not report it ignored, or (c) it is `analysis_options.yaml` (or a `pubspec.lock` that exists in the snapshot) absent from the snapshot, present on disk and not ignored. A package's `pubspec.yaml` is always in the snapshot when the package exists, so (c) does not apply to it. When any path is divergent, tests are not run. One finding at the first divergent path in path order (for case (b), at the import directive in the first importing file in path order). Message: `Affected tests were not run: <n> file(s) they execute differ from the working tree (uncommitted changes, untracked files, or another checked-out commit).` Severity of this dirty-skip finding is always `warning` (severity-locked); configuring `rules: tests/affected: error` does not elevate it. Failed-test findings follow the configured severity of `tests/affected`.
- Otherwise run, per package, `flutter test` (when the package depends on the Flutter SDK) or `dart test`, with the affected files as arguments and machine-readable output. Re-check divergence after the run with the same closure; if it diverged during the run, discard results and report the same warning.
- One finding per failed test. Location: the test's line in its file. Message: `Test failed: <test name>.`
- A run that fails before any test executes (compilation error, missing dependency) yields one finding at `<first affected file>:1:1`: `Tests could not be run: <first line of the tool's error>.`
- Loader pseudo-tests from `dart test --reporter json` have name exactly `loading <suite path>`, empty `groupIDs`, and no `url`/`line`. Only those count as startup/loading; a real test whose name starts with `loading ` is reported as a failed test.

## `stagelatch`

### `stagelatch/invalid-ignore`

- A `stagelatch:ignore` comment that names a rule ID unknown to the running version (ADR-0010), in a changed file.
- Location: the rule ID inside the comment. Message: `Unknown rule "<id>" in stagelatch:ignore.`
- Reported by the suppression filter, not by a check. It cannot itself be suppressed inline.

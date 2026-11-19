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
- No version solving is performed and transitive dependencies are not checked.

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

## `l10n`

Phase: verify. Trigger: a changed `l10n.yaml` or `.arb` file; `unused-key` also triggers on any changed `.dart` file.

Setup, per package with an `l10n.yaml`: `arb-dir` (default `lib/l10n`) and `template-arb-file` (default `app_en.arb`). Keys starting with `@` are metadata and are not message keys.

### `l10n/unparseable`

- A changed `.arb` file in the ARB directory is not valid JSON or its root is not an object. Location: where the parser failed. Message: `<file> is not valid JSON: <reason>.`

### `l10n/missing-key`

- A message key of the template that is absent from another `.arb` file of the ARB directory.
- Location: the key in the template. Message: `Key "<key>" is missing in <file>.`

### `l10n/placeholder-mismatch`

- For a key present in both the template and a translation: the set of ICU argument names in the two messages differs. Argument names are collected from `{name}`, `{name, plural, ...}`, `{name, select, ...}` and nested messages; quoted text (`'{'`) is skipped.
- Location: the key in the translation. Message: `Placeholders of "<key>" differ from the template: expected {<sorted names>}, found {<sorted names>}.`

### `l10n/unused-key`

- A template key whose name does not appear as an identifier in any non-generated `.dart` file of the package. Generated files are those under the l10n output directory and those matching `codegen.generated_suffixes`.
- This rule scans the whole package; it is the only rule that is not change-aware.
- Location: the key in the template. Message: `Key "<key>" is not referenced by any Dart file.`

## `assets`

Phase: verify. Trigger: a changed `pubspec.yaml`, or a changed or deleted file under a directory of `assets.roots`. Paths matching `assets.ignore` are exempt.

A file is **declared** when the `flutter: assets:` list of its package's pubspec contains its exact path, or its directory followed by `/`, or the directory one level up when the file sits in a resolution variant directory (a directory named like `2.0x`). Directory entries are not recursive, as in Flutter. Font files listed under `flutter: fonts:` are declared.

### `assets/missing`

- A declared file path that is not in the snapshot, or a declared directory with no file in the snapshot.
- Location: the entry in `pubspec.yaml`. Message: `Asset "<entry>" is declared but does not exist.`

### `assets/undeclared`

- A changed file under an asset root that is not declared.
- Location: `file:1:1`. Message: `File is under "<root>" but is not declared in pubspec.yaml.`

### `assets/max-file-size`

- A changed file under an asset root whose blob is larger than `assets.max_file_size`.
- Location: `file:1:1`. Message: `File is <size>, larger than the limit of <limit>.` Sizes are printed with one decimal and the unit of the limit.

## `tests`

A **test file** is a `.dart` file under a package's `test/` directory whose name ends with `_test.dart`. A **test call** is a call to a function named in `tests.functions`. Its **key** is the list of enclosing group descriptions followed by its own description; calls whose description is not a string literal use the source text of the argument.

### `tests/solo`

Phase: verify. Trigger: a changed test file.

- A test call with a `solo` argument that is not the literal `false`.
- Location: the `solo` argument. Message: `"solo" must not be committed: it silently skips every other test.`

### `tests/new-skip`

Phase: verify. Trigger: a changed test file.

- A test call with a `skip` argument that is not the literal `false` or `null`, or carrying a `@Skip` annotation, whose key has no skipped counterpart in the base version of the file. Skips that already existed in the base are not reported.
- Location: the `skip` argument or annotation. Message: `Test "<description>" was skipped in this change.`

### `tests/affected`

Phase: verify. Trigger: any changed `.dart` file. Entry points: pre-push and `ci`.

- **Affected test files:** changed test files, plus test files that import a changed file directly or transitively.
- **Dirty closure:** if any affected test file, or any file on an import chain from it to a changed file, differs between the snapshot and the working tree, tests are not run. One finding with severity `warning` at the first such file: `Affected tests were not run: <n> affected file(s) have uncommitted changes.`
- Otherwise run, per package, `flutter test` (when the package depends on the Flutter SDK) or `dart test`, with the affected files as arguments and machine-readable output.
- One finding per failed test. Location: the test's line in its file. Message: `Test failed: <test name>.`
- A run that fails before any test executes (compilation error, missing dependency) yields one finding at `<first affected file>:1:1`: `Tests could not be run: <first line of the tool's error>.`

## `stagelatch`

### `stagelatch/invalid-ignore`

- A `stagelatch:ignore` comment that names a rule ID unknown to the running version (ADR-0010), in a changed file.
- Location: the rule ID inside the comment. Message: `Unknown rule "<id>" in stagelatch:ignore.`
- Reported by the suppression filter, not by a check. It cannot itself be suppressed inline.

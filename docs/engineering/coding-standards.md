# Coding standards

Status: **Approved (2026-11-12).** These rules are checked in review. Where a lint can enforce a rule, the lint is the enforcement and the text here is the explanation.

## 1. Toolchain

- Dart SDK constraint: `^3.13.0`.
- Lints: `very_good_analysis` 11 with `strict-casts`, `strict-inference` and `strict-raw-types`.
- `dart analyze --fatal-infos` must print `No issues found!`. Zero warnings, zero infos.
- `dart format --output=none --set-exit-if-changed .` must exit 0. Default page width (80).

`analysis_options.yaml`, exactly:

```yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    todo: error
```

A lint is never disabled project-wide. A single-line `// ignore:` needs a reason on the same line and is called out in the pull request description.

## 2. Dependencies

Allowed runtime dependencies, all from the Dart team's verified publishers:

| Package | Constraint | Used by |
|---|---|---|
| `args` | `^2.7.0` | cli |
| `collection` | `^1.19.1` | any |
| `crypto` | `^3.0.8` | application (fingerprints) |
| `glob` | `^2.2.0` | application |
| `meta` | `^1.19.0` | any |
| `path` | `^1.9.1` | infrastructure, cli |
| `pub_semver` | `^2.2.1` | checks, application |
| `source_span` | `^1.10.2` | infrastructure |
| `yaml` | `^3.1.4` | infrastructure |

Dev dependencies: `test ^1.33.0` and `very_good_analysis ^11.0.0`. No coverage package is needed: `dart test --coverage-path` writes the lcov report itself.

`analyzer` and `dart_style` are added only if the spike selects them (ADR-0008), and only `infrastructure/dart/` may import them.

Adding any other runtime dependency requires an ADR that states what it replaces, who publishes it and why writing the code ourselves is worse. No mocking library, no code generation, no DI container.

`pubspec.lock` is committed: this is an application.

## 3. Types and immutability

- Classes are `final` unless designed for extension. Sum types are `sealed` and consumed with exhaustive `switch`; never add a `default` branch to a switch over a sealed type or enum.
- Constructors are declared without repeating the class name, as the `unnecessary_type_name_in_constructor` lint of Dart 3.13 requires: `const new(this.path)`, `const new wholeFile(RepoPath path)`, `factory(String value)`, `factory parse(String value)`. `dart fix --apply` rewrites the old form.
- A class that overrides `==` and `hashCode` is annotated `@immutable` (`package:meta`); the `avoid_equals_and_hash_code_on_mutable_classes` lint requires it.
- Fields are `final`. Constructors are `const` where possible. Collections received by a constructor are stored as unmodifiable copies.
- Value types implement `==` and `hashCode` by hand and have a test for both. No equality package.
- No `dynamic`. Data from YAML, JSON or a process is narrowed with pattern matching, never with `as`.
- No `!`. If a value cannot be null, the type says so; if it can, handle it.
- `late` is allowed only for fields initialized in the same constructor body that declares them.
- Ports are `abstract interface class`. Adapters are named after their technology (`GitCliRepository`); fakes are named `Fake<Port>` and live in `test/support/`.
- Public API of `package:stagelatch` is empty until 1.0.0. Everything is under `lib/src`.

## 4. Functions and files

- One public type per file; the file is the snake_case of the type.
- A function does one thing. If you need a comment to separate its phases, it is two functions.
- Boolean parameters are named. Positional booleans are not allowed.
- No function reads global state. Clock, environment, working directory and I/O arrive through parameters or constructor-injected ports.

## 5. Asynchrony and processes

- Every `Future` is awaited or explicitly passed to `unawaited` with a comment saying why.
- A spawned process is always closed in a `finally`, including the persistent `git cat-file --batch`.
- Concurrency is `Future.wait` over a list built in a defined order. Results are consumed by index, never by completion order.
- No isolates before a measurement shows they are needed.

## 6. Errors

- User content problems are findings. Invocation problems are `UsageException`. Config problems are `ConfigException`. Everything else is a bug and surfaces as exit 70.
- `catch` always names a type. The only `catch (Object)` is in `cli/runner.dart`.
- Never swallow an error. Never return `null` to mean "something failed".
- An error message says what happened, on which path or command, and what the user can do next.

## 7. Comments

Comments are part of the deliverable and are reviewed like code.

**Required**

1. A `///` doc comment on every public class, constructor, method, field and top-level function. The first sentence says what it is or does; further paragraphs give the contract: units, ranges, nullability meaning, ordering guarantees.
2. A library-level doc comment at the top of every file under `lib/src` stating the file's single responsibility.
3. A comment on every git invocation explaining each non-obvious flag.
4. A comment wherever code handles an edge case from a spec or ADR, citing it.
5. A comment on every constant that encodes a limit, with the reason for the value.

**Forbidden**

- Comments that restate the code.
- Commented-out code.
- `TODO` without an issue link (the analyzer setting above makes a bare `TODO` an error).
- Change history ("fixed in v2", "added by ..."): git has it.

Example of the expected level:

```dart
/// Lists the paths whose snapshot content differs from the working tree.
///
/// The result drives the analysis overlay (ADR-0001): every path returned
/// here must be shown to the Dart toolchain with its snapshot content,
/// otherwise unstaged edits leak into the verdict.
///
/// Paths are sorted and unique. Deleted files are included.
Future<Set<RepoPath>> divergingFromWorktree(SnapshotRef ref) async {
  // -z: NUL-separated output, the only form that is safe for paths with
  //     newlines, quotes or non-ASCII characters.
  // --no-renames: we need both sides of a rename as plain paths.
  final output = await _git.run(
    ['diff', '--name-only', '-z', '--no-renames', ..._treeArgs(ref)],
  );
  return _parsePaths(output);
}
```

## 8. Output and messages

- Nothing calls `print`, `stdout` or `stderr` outside `infrastructure/reporters/` and `cli/`.
- Every user-facing string is listed in a spec. Tests assert the exact text.
- Messages are in English, sentence case, end with a period, contain no emoji, and name paths relative to the repository root.
- Finding messages never quote file content from files flagged by `sensitive-files` (see [`security.md`](security.md), S5).

## 9. Tests

See [`testing.md`](testing.md). In short: test first, fakes over mocks, one behavior per test, exact assertions.

## 10. Review checklist

- [ ] Imports respect the module table; `layering_test` passes.
- [ ] Every public member has a doc comment that states its contract.
- [ ] No new dependency, or an ADR justifies it.
- [ ] No `dynamic`, `!`, bare `catch`, `print`, or unlisted user-facing string.
- [ ] New behavior has a failing-first test; edge cases from the spec are covered.
- [ ] Output order is defined by a sort.
- [ ] The security checklist in [`security.md`](security.md) passes.

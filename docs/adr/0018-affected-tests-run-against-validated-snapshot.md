# ADR-0018: Affected tests run against the validated snapshot, or not at all

- Status: Accepted
- Date: 2026-11-21

## Context

`tests/affected` (`0.3.0`) is the first feature that executes project code. Every other check reads blobs from the snapshot (ADR-0001), and Dart analysis runs on a materialized copy of it. A test runner cannot do that cheaply: `dart test` and `flutter test` need the package's `.dart_tool`, assets, fixtures and goldens, none of which a Dart-and-YAML materialization holds.

So the tests run on the working tree. That is safe only when the working tree holds exactly the code the snapshot holds, for the Dart files the tests import and for the configuration that selection tracks (the closure below). Files selection cannot see are documented limitations. If the tree does not match, a green run vouches for code that is not being published, and a red one blames code that is not being published. `CLAUDE.md` already states the guard: `tests/affected` does not run when affected files have uncommitted changes. Reading that guard against the current implementation shows three holes:

1. **Untracked files.** The list of divergent paths is `git diff --name-only -z --no-renames [<sha>]` ([`git.md`](../specs/git.md#5-files-that-differ-from-the-working-tree)). It never contains an untracked file. The import graph keeps an edge to a target that is absent from the snapshot ([`dart-toolchain.md`](../specs/dart-toolchain.md#3-import-graph)), so a test that imports an untracked `.dart` file is affected, finds no divergence, and runs against code the commit does not contain. This is the exact failure ADR-0001 rejected for analysis.
2. **Pre-push of a branch that is not checked out.** The snapshot is the pushed commit (ADR-0007) and the working tree is another commit. Nearly every file of the closure differs, and any rule that only looked at files changed by the push would still run tests on the wrong tree.
3. **Non-Dart dependencies.** A change to `pubspec.yaml`, `pubspec.lock` or `analysis_options.yaml` alters how the package resolves its dependencies and can change the analysis and compilation options its suite inherits, yet no test imports those files, so import-based selection ignores them.

Evidence that materializing the snapshot for tests is not the way out: `MaterializedSnapshot` copies only `.dart`, `.yaml` and `.yml` files (about 0.25 s for 2,472 files). Tests also need fixtures, assets and goldens, the package's `.dart_tool`, and for Flutter a complete tool setup. Copying all of that, or running `pub get` in the copy, would change what `CLAUDE.md` and the write targets of [`security.md`](../engineering/security.md) S3 allow, and would cost far more than the 0.25 s that is negligible next to the roughly 13 s `analyze` takes on the spike's 2,435-file Flutter app.

## Decision

**Tests run on the working tree. They run only when the working tree provably equals the snapshot for the closure defined below (the Dart files the tests import that are in the snapshot or would be committed, plus the package configuration); otherwise they are skipped with a warning.** The three holes are closed by the rules below. The guarantee does not extend to everything a test process reads; see the limitations.

### The closure

For a run, the **closure** is:

- the affected test files (changed test files, and test files that import a changed or deleted file, directly or transitively);
- every file in the transitive import closure of those test files: `import`, `export` and `part` edges, conditional branches included, across the packages of the repository. This contains every file on a chain from a test to a changed file, and also the unchanged files the same tests execute;
- for each package that owns an affected test, its `pubspec.yaml` and `analysis_options.yaml`, and its `pubspec.lock` **only when that path exists in the snapshot** (hole 3). Libraries often gitignore the lock; a lock that exists only on disk was never committed, so it is out of scope, the same class of limitation as fixtures.

Dependencies from pub.dev are outside the closure; when the lock is committed it pins them, and it is inside the closure.

### Divergence

A path of the closure is **divergent** when any of these holds:

1. It differs between the snapshot and the working tree: it is in `git diff --name-only -z --no-renames [<sha>]`.
2. It is the target of an import edge of the closure, it is absent from the snapshot, a regular file of that path exists on disk under the repository root, **and git would track it**, i.e. it is not ignored (hole 1). The candidates are the edge targets missing from the snapshot; the ignored ones are then removed with one batched `git check-ignore --stdin -z`. A file that `.gitignore` hides is intentional local state (typically generated code), never a commit candidate, so it does not skip. An untracked, non-ignored `.dart` file does.
3. It is `pubspec.yaml` or `analysis_options.yaml` of an owning package, it is absent from the snapshot, a file of that path exists on disk, and it is not ignored. `pubspec.lock` has no such case: absent from the snapshot, it is outside the closure. A committed `pubspec.lock` can still diverge by rule 1.

When any path is divergent, no process is started. The check reports one `warning`; the skip does not fail the push or the CI run.

### Pre-push of a branch that is not checked out (hole 2)

No special case. The same divergence test runs against the pushed commit. When the working tree is another commit, the closure diverges and tests are skipped. This is intended and safe: the hook cannot execute code it has not validated. The warning text says that the working tree does not match the snapshot, so the cause is visible. In `ci` the checkout is the head commit, so the closure normally does not diverge.

### Non-Dart dependencies (hole 3)

- A change to `pubspec.yaml` or `analysis_options.yaml` of a package, or to a `pubspec.lock` that exists in the snapshot, selects **all** tests of that package. For `pubspec.yaml` and `analysis_options.yaml` this is parity with `analyze.scope: affected`, which widens to the whole package; `analysis_options.yaml` can also change the analysis and compilation options the suite inherits. A lock that was never committed has no change in the changeset and selects nothing.
- If one of those files diverges (rules 1 and 3 above) for a package that has selected tests, the closure is divergent and tests are skipped.
- **Documented limitations.** Selection ignores these files, and their divergence alone does not skip: fixtures, goldens and assets; `dart_test.yaml`; `flutter_test_config.dart`; `pubspec_overrides.yaml`; `build.yaml`; and other config or data files that no `import`, `export` or `part` reaches. A test run can therefore read a file that differs from the snapshot's, or use a lock or generated file that is not in the snapshot. The README says so.

### Execution rules

- The divergence test runs immediately before the first process is started, and again after the last one exits. The second run uses the same rules and the closure computed at the start. If the closure diverged during the run, the results are discarded and the same warning is reported, so an edit made while tests run cannot produce a verdict about code that was never validated. A project whose tests write tracked files into the closure therefore has its results discarded.
- `tests/affected` may start project test processes only on `pre-push` and `ci`. `pre-commit`, `doctor`, `why`, `init`, `install`, `uninstall` and `baseline` never start one. `why` reads the import graph and runs nothing.
- Processes are started per S1 and S14 of [`security.md`](../engineering/security.md): an argument list, never a shell; the inherited environment, with no secret ever injected; stdout and stderr are untrusted input, parsed as machine-readable events and sanitized before display.
- `tests/affected` stays in the default `pre-push` list and out of `pre-commit`. The time budget only warns (ADR-0003).
- **This repository** enables `tests/affected` in the `pre-push` list of its `stagelatch.yaml` to dogfood the rule (plan 04, Task 10). The `ci` hook list defaults to the union of the others, so the dogfood CI job runs it too once the rule lands. If that job's time becomes a problem, the owner lists `ci` explicitly without `tests/affected`; the default does not change.
- A pull request that changes the tests, or the code they import, makes `stagelatch ci` execute that code, like any `dart test` step in a CI workflow. The README and `action.yml` say so, and that for pull requests from forks the project's usual restrictions on secrets apply.

### Determinism

The verdict is a pure function of the snapshot, the closure check and the exit status and events the test process produces (ADR-0003). A flaky test gives a flaky verdict; that flakiness belongs to the project's tests, not to stagelatch, and is the one exception ADR-0003 already records.

## Consequences

- A green `tests/affected` means: these tests ran against files identical to the snapshot's, for every Dart file of their import closure that is in the snapshot or would be committed, and for `pubspec.yaml`, `analysis_options.yaml` and, when committed, `pubspec.lock`. It does not mean everything the tests execute matched: the documented limitations above (fixtures, goldens, assets, `dart_test.yaml`, `flutter_test_config.dart`, `pubspec_overrides.yaml`, `build.yaml`, other non-imported files, and gitignored files) are outside it. A skip is always visible as a warning, never as a silent pass.
- Pushing a branch that is not checked out usually skips tests. The guarantee still comes from `stagelatch ci` on the pull request (ADR-0005).
- A closure that holds a file with unstaged edits skips tests, even when that file is not one the push changed. Developers who `git add -p` often will see more skips than with a chain-only rule; that is the cost of the guarantee, and the warning names the first divergent file.
- A project that does not version its generated Dart files (`codegen.generated_files_committed: false`) has them gitignored, absent from the snapshot and present on disk after `build_runner`, locally and in `ci`. They are ignored, so they never skip, and the verdict is computed with generated code the snapshot does not hold. That is a limitation, not a guarantee: the generated files are outside the closure's guarantee, and what covers them is the generator being deterministic over the committed sources. If such a project does not gitignore them, they are untracked and non-ignored, and tests are skipped until they are ignored or committed. Documented rather than special-cased.
- A gitignored `pubspec.lock` (common in libraries) is outside the closure; `ci` after `pub get` does not skip because of it, and the resolution it pins is not covered by the guarantee.
- Cost: the `git diff --name-only` that `analyze` already needs, one file system test per import edge target that is missing from the snapshot, and one batched `git check-ignore` over those that exist. No materialization for tests.
- New acceptance scenarios (AC-25 to AC-27 in [`testing.md`](../engineering/testing.md)): an affected test importing an untracked non-ignored file (skips) and an ignored one (does not skip); a push of a branch that is not checked out; a divergent `pubspec.yaml` or committed `pubspec.lock`, and a gitignored `pubspec.lock` (does not skip).
- The import graph must expose the forward closure of a set of files, with edges to absent targets, for the divergence test.

## Alternatives rejected

- **Materialize the snapshot and run the tests there.** Needs fixtures, assets, goldens, `.dart_tool` or a `pub get`, and for Flutter a full setup; the existing materialization copies only `.dart`, `.yaml` and `.yml`. It would change `CLAUDE.md`, the S3 write targets and the cost model, for a guarantee the divergence test gives more cheaply. Not needed once the three holes are closed; revisit only with a new ADR.
- **Run on the working tree without the guard.** Makes the verdict depend on whatever the developer has on disk, which ADR-0001 exists to prevent.
- **Chain-only closure** (only files on a path from a test to a changed file). Misses an unchanged helper that the tests import and that has unstaged edits, so the executed code would differ from the snapshot. The forward import closure is a superset and costs only extra skips.
- **Count ignored files as divergent (file system test only, no ignore filter).** The first draft of this ADR did that. It made every project with a gitignored `pubspec.lock` or gitignored generated code skip forever, `ci` included, so the gate could never give its guarantee there. Intentionally ignored files are now a documented limitation.
- **Detect untracked files with `git ls-files --others --exclude-standard` over the whole tree.** Needs a full-tree listing; candidate edge targets plus `git check-ignore` on them is bounded by the closure.
- **Stash or reset the working tree to run tests.** Mutates user state; rejected by ADR-0001.
- **Fail the push when tests are skipped.** A skip is not a failure of the code; blocking would make every non-checked-out push fail. CI is the guarantee.

# Testing strategy

Status: **Approved (2026-11-12).**

## 1. Rules

- **Test first.** Every task in every plan starts with a failing test, run and seen to fail for the expected reason, before production code is written.
- **Fakes, not mocks.** Each port has one hand-written in-memory fake in `test/support/`. No mocking library.
- **One behavior per test.** The test name is a sentence stating the behavior.
- **Exact assertions.** Assert the whole finding (rule, severity, message, location), not `isNotEmpty`.
- **No sleeps, no real clock, no network.** Time comes from `FakeClock`.
- A bug fix starts with a test that reproduces the bug.

## 2. Test kinds

| Kind | Location | Subject | Uses |
|---|---|---|---|
| Architecture | `test/architecture/` | import rules between modules | source files only |
| Unit | `test/domain/`, `test/checks/`, `test/application/` | values, rules, pipeline, config, baseline | fakes |
| Adapter | `test/infrastructure/` | one adapter against the real thing it wraps | real git in a temp repo, real files |
| Golden | `test/infrastructure/reporters/` | exact reporter output | files under `test/goldens/` |
| CLI | `test/cli/` | argument parsing, exit codes, wiring | in-process runner with fake I/O |
| Acceptance | `test/acceptance/` | whole scenarios through the real CLI | real git repositories |

Tags: adapter and acceptance tests carry `@Tags(['git'])`; scenarios that only make sense on one OS are skipped elsewhere with a stated reason.

## 3. Support code

`test/support/temp_repo.dart`, used by adapter and acceptance tests:

```dart
final class TempRepo {
  static Future<TempRepo> create({bool initialCommit = true, Map<String, String> gitConfig = const {}});
  String get root;
  Future<void> write(String path, String content);
  Future<void> writeBytes(String path, List<int> bytes);
  Future<String> read(String path);          // working tree content
  Future<void> delete(String path);
  Future<void> stage(String path);
  /// Puts [content] in the index for [path] without touching the working
  /// tree. This is how partial staging (`git add -p`) is reproduced exactly.
  Future<void> stageContent(String path, String content);
  Future<void> commit(String message);
  Future<String> git(List<String> args, {String? stdin, Map<String, String> env = const {}});
  /// Runs the CLI in-process with this repository as working directory.
  Future<CliResult> stagelatch(List<String> args, {String stdin = '', Map<String, String> env = const {}});
  Future<void> dispose();
}

final class CliResult { int get exitCode; String get stdout; String get stderr; }
```

- `TempRepo.create` sets `user.name`, `user.email`, `commit.gpgsign=false`, `core.autocrlf=false` and `init.defaultBranch=main` locally, so tests do not depend on the machine's git config.
- The CLI takes its working directory, environment and streams as parameters. That is what lets acceptance tests run in-process and in parallel.
- A small number of tests spawn the real executable through a real `git commit` to prove the hook script works. They are tagged `e2e`.

## 4. Mandatory acceptance scenarios

Each scenario is one test file under `test/acceptance/`. IDs are stable and referenced by plans.

| ID | Scenario | First needed in |
|---|---|---|
| AC-01 | Partial staging: staged part clean, unstaged part violating, and the reverse | 0.1.0-dev.1 |
| AC-02 | Rename, with and without content change | 0.1.0-dev.1 |
| AC-03 | Delete of a file that had findings | 0.1.0-dev.1 |
| AC-04 | Binary file staged | 0.1.0-dev.1 |
| AC-05 | First commit, no `HEAD` | 0.1.0-dev.1 |
| AC-06 | Merge in progress: reduced changeset | 0.1.0-dev.1 |
| AC-07 | Rebase in progress | 0.1.0-dev.1 |
| AC-08 | `core.hooksPath` set by another tool; third-party hook present | 0.1.0-dev.1 |
| AC-09 | Linked worktree (`git worktree add`): install and run | 0.1.0-dev.1 |
| AC-10 | CRLF: `core.autocrlf=true`, and CRLF blobs committed as-is | 0.1.0-dev.1 |
| AC-11 | Paths with spaces, quotes, non-ASCII characters and a newline | 0.1.0-dev.1 |
| AC-12 | No TTY: stdin closed, no prompt, no escape sequences | 0.1.0-dev.1 |
| AC-13 | Real `git commit` fires the installed hook (all three OSes) | 0.1.0-dev.1 |
| AC-14 | Tool missing from PATH: hook prints the notice and the commit succeeds | 0.1.0-dev.1 |
| AC-15 | `git commit -a` and `git commit <path>` (git uses a temporary index) | 0.1.0-dev.1 |
| AC-16 | Staged config beats unstaged config (ADR-0015) | 0.1.0-dev.1 |
| AC-17 | Format autofix: clean file, partially staged file, executable bit kept | 0.1.0 |
| AC-18 | Snapshot isolation: an unstaged edit in a dependency, an untracked imported file, and a file deleted only in the index do not change the verdict | 0.1.0 |
| AC-19 | Pre-push: existing branch, new branch, branch deletion, tag push | 0.1.0 |
| AC-20 | `ci` in a shallow clone fails with the `fetch-depth` message | 0.1.0 |
| AC-21 | Repository with two packages: each file checked in its own package | 0.1.0 |
| AC-22 | Symlink and submodule entries are skipped by content checks | 0.1.0 |
| AC-23 | Baseline: old finding passes, new finding blocks, line shifts do not matter | 0.2.0 |
| AC-24 | `tests/affected` with uncommitted changes in the affected closure | 0.3.0 |
| AC-25 | `tests/affected`: an affected test imports an untracked non-ignored `.dart` file: no process is started and the warning is reported; the same import of a gitignored `.dart` file (generated code) does not skip | 0.3.0 |
| AC-26 | `tests/affected` on a pre-push of a branch that is not checked out: the closure diverges, tests are skipped with the warning, the push is not failed | 0.3.0 |
| AC-27 | `tests/affected` and package configuration: a change to `pubspec.yaml` or `pubspec.lock` selects all tests of the package; an unstaged edit to a committed `pubspec.lock`, or an untracked non-ignored `pubspec.yaml` or `analysis_options.yaml`, skips tests; a gitignored `pubspec.lock` present only on disk does not; an unstaged edit to a fixture, `dart_test.yaml` or `build.yaml` alone does not | 0.3.0 |
| AC-28 | Pub workspace: a member's files are analyzed with the workspace root's package config; `pubspec/lockfile-out-of-sync` reads the root lock; `tests/affected` selects and runs the tests of a member when a file of another member changes; `why` explains it | 0.3.0 |

## 5. Determinism test

`test/acceptance/determinism_test.dart` runs the same scenario twice with `--reporter json`, removes the duration fields, and asserts the two outputs are byte-identical. It also runs once with a shuffled check registry order and asserts the same, and once with a cold and once with a warm facts cache ([`dart-toolchain.md`](../specs/dart-toolchain.md#61-the-facts-cache)): the three outputs must be identical.

## 6. Coverage

- Line coverage of `lib/src/domain`, `lib/src/checks` and `lib/src/application`: at least 90%, enforced in CI by `tool/check_coverage.dart`.
- `infrastructure` and `cli` have no numeric threshold; they are covered by adapter and acceptance tests, and every public adapter method has at least one.
- Coverage is a floor, not a goal. A covered line with a weak assertion is a review finding.

## 7. Commands

```bash
dart format --output=none --set-exit-if-changed .
```

```bash
dart analyze --fatal-infos
```

```bash
dart test
```

```bash
dart test --coverage-path=coverage/lcov.info && dart run tool/check_coverage.dart
```

All four run on every pull request, on Dart stable and beta, on Ubuntu, macOS and Windows, with two exceptions: the format check runs on stable only, because formatter output is specific to an SDK release (ADR-0008), and the coverage floor is checked once, on Ubuntu with stable. Only that job passes `--coverage-path` to `dart test` (see section 9 for why); the other five run plain `dart test`.

## 8. Platform notes

- Never build a path with string concatenation in a test; use `package:path` for OS paths and plain `/` for `RepoPath`.
- Windows has no executable bit in the file system; assert the mode through `git ls-files -s`, not through file permissions.
- Windows may hold file locks briefly after a process exits; `TempRepo.dispose` retries deletion a bounded number of times.

## 9. Known CI failure: a suite fails to load

**Symptom.** `dart test` reports `Failed to load "<suite>": Connection closed before full header was received, uri = http://127.0.0.1:<port>/<token>/ws`. It happens before any assertion of that suite counts, and it hits pure suites (`test/domain/rule_id_test.dart`) as well as suites that spawn `git`.

**Where it was seen.** Windows jobs (pull request 12, which is why they run with `--concurrency=1`) and `ubuntu-latest / dart beta` on 2026-11-20 (run 44683972741, two suites, green on rerun). After PR #53, run 44848100638 (`ubuntu-latest / dart stable`, the coverage job, push of #66 onto develop) failed with `Failed to load "test/application/environment_test.dart": Connection closed before full header was received`. Every other red run in the history was a real failure and did not carry this message.

**Coverage-job occurrences since PR #53.** Count: **1** — run 44848100638. That job is the only one that still passes `--coverage-path`, which matches the hypothesis from #53 (the failure only appears where `--coverage-path` is on). Three occurrences mean moving coverage to its own job with `--concurrency=1`.

**What the evidence says.**

- The URI is the VM service WebSocket (`/ws`). With `test_core` 0.6.x the runner opens it only for coverage (`vm/platform.dart` calls `_gatherCoverage` through `package:coverage`'s `collect`), or in `--debug` mode. A plain `dart test` never opens it.
- Every occurrence had `--coverage-path` on. Occurrences before PR #53 were in jobs that did not read the report; the one after #53 was on the coverage job itself.
- It did not reproduce locally: 0 failures in 160 runs of `test/domain` (macOS, Dart stable), 80 with coverage and 80 without.
- No upstream issue carries the exact message for this path. `dart-lang/sdk#56474` is the same `HttpException` text in an unrelated caller.

**What is not established.** How the error escapes the `retry` loop of `package:coverage`, which repeats on any exception. This is a hypothesis about contention on the VM service connection, not a confirmed root cause.

**What CI does.** Only the job that checks the coverage floor (Ubuntu, stable) passes `--coverage-path`. The other five jobs no longer open that connection at all. Nothing is retried automatically: a red job is a red job.

**If it happens again** on the coverage job, rerun that job once with `gh run rerun <run-id> --failed`, and add the run id to this section. A suite failing with an assertion, a timeout or a different message is a real failure and is never rerun blindly. Three occurrences on the coverage job mean the coverage step should move to its own job with `--concurrency=1`.

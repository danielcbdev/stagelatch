# Recorded test tool output

Each `.jsonl` file is the standard output of one real run of the test tool,
used by `test/infrastructure/dart/test_event_parser_test.dart`. Nothing was
written by hand.

## Recorded with

- Date: 2026-11-21, macOS (arm64).
- Dart SDK 3.13.4 (stable), `test` 1.33.0 (`test_core` 0.6.21), JSON protocol
  `0.1.1`.
- Flutter 3.47.5 (stable), whose bundled Dart SDK is 3.13.4. Its runner reports
  `runnerVersion: null`.

## Commands

Dart, in a throwaway package that depends on `package:test`:

```sh
dart --suppress-analytics test --reporter json -- test/a_test.dart   # all_pass
dart --suppress-analytics test --reporter json -- test/b_test.dart   # one_failure
dart --suppress-analytics test --reporter json -- test/d_test.dart   # error_result
dart --suppress-analytics test --reporter json -- test/c_test.dart   # compile_error
dart --suppress-analytics test --reporter json -- test/e_test.dart   # helper_location
```

Flutter, in a throwaway package that depends on `flutter_test`:

```sh
flutter test --machine -- test/w_test.dart                           # flutter_noise
```

## What each file shows

| File | Content |
|---|---|
| `all_pass` | Two passing tests; the hidden loader pseudo-test passes. |
| `one_failure` | `g fails` (an `isFailure` error, `result: failure`), a skipped test (`skipped: true`, `result: success`) and a passing one. |
| `error_result` | `throws` has two `error` events and `result: error`; `loading spinner` is a real failing test whose name starts with `loading `. |
| `compile_error` | The loader pseudo-test `loading test/c_test.dart` has an `error` event (`Failed to load "...":` then the diagnostic) and `result: error`, `hidden: false`. No real test starts. |
| `helper_location` | A test declared by a helper in `test/helper.dart` and called from `test/e_test.dart`: `url` points at the helper, `root_url`, `root_line` and `root_column` at the caller. |
| `flutter_noise` | `flutter test --machine`: absolute `suite.path`, a blank line and a JSON array (`[{"event":"test.startedProcess",...}]`) between events. |

## Edits made after recording

Only the root of the throwaway package was rewritten, so the files do not
depend on the machine: `file:///private/tmp/.../rec` (Dart) and `.../frec`
(Flutter) became `file:///repo`, and the Flutter `suite.path` and loader name
became `/repo/test/w_test.dart`. Process ids and timings are as recorded.

Re-record with the commands above when a new SDK changes the protocol, and
update this file with the new versions.

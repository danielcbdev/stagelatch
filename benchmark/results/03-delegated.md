# Task 3: delegated probe (candidate B)

Recorded on 2026-11-18. Apple M4, macOS 27.2.1. Tool run with `dart run`
(Dart 3.13.4, JIT). Server: `dart --suppress-analytics language-server
--protocol=analyzer --cache=<dir>` of the corpus SDK, Flutter 3.47.8 /
Dart 3.13.7 (AOT snapshot `analysis_server_aot.dart.snapshot`).

Method names were confirmed against the strings of the server snapshot
shipped with that SDK (the SDK ships no protocol document):
`analysis.updateContent`, `analysis.setAnalysisRoots`,
`analysis.setPriorityFiles`, `analysis.getErrors`, `edit.format`,
`server.setSubscriptions`, `server.shutdown`, `server.connected`,
`server.status`.

Order of requests: `analysis.updateContent` (one `add` per overlay),
then `analysis.setAnalysisRoots`, then `analysis.setPriorityFiles` with
the files to diagnose, then one `analysis.getErrors` per file (sent
together, consumed by index), then `edit.format` per file with
`selectionOffset: 0, selectionLength: 0` and no `lineLength`, then
`server.shutdown` in a `finally` (killed after 5 s if still alive).

## Overlay proof (step 3)

```
$ dart run benchmark/bin/run_probe.dart delegated s3
delegated s3 overlays=4 files=3
  ERROR argument_type_not_assignable lib/features/badges/biz/bloc/badges_bloc.dart@963+9: The argument type 'String' can't be assigned to the parameter type 'BadgesStatus?'. 
  INFO directives_ordering lib/features/badges/domain/badge_catalog.dart@40+38: Sort directive sections alphabetically.
  WARNING unused_local_variable lib/features/badges/domain/badge_catalog.dart@2482+5: The value of the local variable 'known' isn't used.
  INFO prefer_const_constructors lib/features/badges/views/widgets/badge_celebrate_sheet.dart@1966+31: Use 'const' with the constructor to improve performance.
  UNFORMATTED lib/features/badges/views/widgets/badge_celebrate_sheet.dart
  phases: start=29ms overlay=13692ms diagnose=24ms format=52ms

$ dart run benchmark/bin/run_probe.dart delegated s3 --no-overlays
delegated s3 overlays=0 files=3
  ERROR undefined_method lib/features/badges/biz/bloc/badges_bloc.dart@922+5: The method 'check' isn't defined for the type 'BadgeRepository'.
  INFO directives_ordering lib/features/badges/domain/badge_catalog.dart@40+38: Sort directive sections alphabetically.
  phases: start=29ms overlay=13822ms diagnose=26ms format=48ms

$ dart run benchmark/bin/run_probe.dart delegated s10
delegated s10 overlays=11 files=10
  ERROR argument_type_not_assignable lib/features/badges/biz/bloc/badges_bloc.dart@963+9: The argument type 'String' can't be assigned to the parameter type 'BadgesStatus?'. 
  INFO directives_ordering lib/features/badges/domain/badge_catalog.dart@40+38: Sort directive sections alphabetically.
  WARNING unused_local_variable lib/features/badges/domain/badge_catalog.dart@2482+5: The value of the local variable 'known' isn't used.
  INFO prefer_const_constructors lib/features/badges/views/widgets/badge_celebrate_sheet.dart@1966+31: Use 'const' with the constructor to improve performance.
  INFO directives_ordering lib/features/quests/domain/quest_board.dart@68+51: Sort directive sections alphabetically.
  UNFORMATTED lib/features/badges/views/widgets/badge_celebrate_sheet.dart
  phases: start=30ms overlay=13836ms diagnose=32ms format=138ms

```

Without overlays the trap is reported as `undefined_method`, the code
`dart analyze` prints, and the pre-existing `directives_ordering` stays.

## Wait strategy (step 4)

Both strategies are correct and give identical diagnostics on `s10`.

- **immediate:** `analysis.getErrors` right after the requests above. The
  protocol delays the response until the file's errors are current.
- **idle:** wait for `server.status` with `isAnalyzing: false` after a
  `true`. Needs `server.setSubscriptions` with `STATUS` first: without it
  the server sends no status and the wait never ends (seen: a 300 s
  timeout). It waits for the whole package, 2,435 files:

```
  phases: start=32ms overlay=13962ms diagnose=13669ms format=37ms
```

**Decision: immediate.** It is what the protocol guarantees and it does
not pay for files nobody asked about.

## Phase timings (step 5, not the official numbers)

Cold, fresh cache directory per run: see the `phases` lines above
(`s3` and `s10` both about 13.8 s). Warm, three consecutive runs sharing
one `--cache` directory, `s10`:

```
  phases: start=29ms overlay=13930ms diagnose=34ms format=147ms
  phases: start=28ms overlay=13100ms diagnose=36ms format=143ms
  phases: start=29ms overlay=12944ms diagnose=46ms format=151ms
```

Almost all of it is spent inside `analysis.setAnalysisRoots`, which
returns after about 12.9 s with or without a warm cache (measured per
request). The cache stays at 6.4 MB (unlinked summaries only), against
127 MB for the embedded probe's byte store.

The per-run cost is a property of the server on Flutter packages, not of
this client:

| Root given to `setAnalysisRoots` (one fresh server each) | Time |
|---|---|
| stagelatch itself (Dart only, about 150 files) | 1.0 s |
| `packages/flutter_floating_bottom_bar` of the corpus (16 files, depends on Flutter) | 5.1 s |
| the corpus package (2,435 files) | 13.2 s |

`dart analyze` of the SDK on the 16-file package, run twice with the
user's own warm server cache: 4.8 s, then 4.1 s.

### Variant: roots are the files, not the package

`setAnalysisRoots` accepts files. With `included` set to the ten files
of `s10`, the server analyzes them and their imports only. Same
diagnostics; the import closure of these files is most of the app, so it
saves little:

```
delegated s10 overlays=11 files=10
  ERROR argument_type_not_assignable lib/features/badges/biz/bloc/badges_bloc.dart@963+9: The argument type 'String' can't be assigned to the parameter type 'BadgesStatus?'. 
  INFO directives_ordering lib/features/badges/domain/badge_catalog.dart@40+38: Sort directive sections alphabetically.
  WARNING unused_local_variable lib/features/badges/domain/badge_catalog.dart@2482+5: The value of the local variable 'known' isn't used.
  INFO prefer_const_constructors lib/features/badges/views/widgets/badge_celebrate_sheet.dart@1966+31: Use 'const' with the constructor to improve performance.
  INFO directives_ordering lib/features/quests/domain/quest_board.dart@68+51: Sort directive sections alphabetically.
  UNFORMATTED lib/features/badges/views/widgets/badge_celebrate_sheet.dart
  phases: start=29ms overlay=12453ms diagnose=33ms format=476ms
  phases: start=29ms overlay=11706ms diagnose=64ms format=450ms
  phases: start=30ms overlay=11214ms diagnose=30ms format=341ms
```

Task 4 checks this variant for parity too.

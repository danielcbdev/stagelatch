# Task 2: embedded probe (candidate A)

Recorded on 2026-11-18. Apple M4, macOS 27.2.1. Tool run with `dart run`
(Dart 3.13.4, JIT); analyzed with the corpus SDK, Flutter 3.47.8 /
Dart 3.13.7. `package:analyzer` 14.7.0, `package:dart_style` 3.1.14.

API used: `AnalysisContextCollectionImpl` (the implementation class, the
only constructor that takes a `byteStore`) over an `OverlayResourceProvider`
wrapping `PhysicalResourceProvider.INSTANCE`, `sdkPath` set to the corpus
SDK; `AnalysisSession.getErrors(path)` per file; `ErrorProcessor.getProcessor`
for the `errors:` section of `analysis_options.yaml`; `DartFormatter` with
the package language version from `package_config.json` and
`formatter: page_width` from the nearest `analysis_options.yaml`.

## Overlay proof (step 2)

With overlays, the staged error and warning are reported and the unstaged
trap is not. Without overlays the probe sees the working tree: the staged
paths are back at the pinned content (the scenario applies `staged.patch`
to the index only), so the staged findings vanish and the trap appears.

```
$ dart run benchmark/bin/run_probe.dart embedded s3
embedded s3 overlays=4 files=3
  ERROR argument_type_not_assignable lib/features/badges/biz/bloc/badges_bloc.dart@963+9: The argument type 'String' can't be assigned to the parameter type 'BadgesStatus?'. 
  WARNING unused_local_variable lib/features/badges/domain/badge_catalog.dart@2482+5: The value of the local variable 'known' isn't used.
  UNFORMATTED lib/features/badges/views/widgets/badge_celebrate_sheet.dart
  phases: overlay=0ms start=290ms diagnose=12494ms format=72ms

$ dart run benchmark/bin/run_probe.dart embedded s3 --no-overlays
embedded s3 overlays=0 files=3
  ERROR undefined_instance_member_read lib/features/badges/biz/bloc/badges_bloc.dart@922+5: The member 'check' isn't defined for the type 'BadgeRepository'.
  phases: overlay=0ms start=282ms diagnose=12586ms format=74ms

$ dart run benchmark/bin/run_probe.dart embedded s10
embedded s10 overlays=11 files=10
  ERROR argument_type_not_assignable lib/features/badges/biz/bloc/badges_bloc.dart@963+9: The argument type 'String' can't be assigned to the parameter type 'BadgesStatus?'. 
  WARNING unused_local_variable lib/features/badges/domain/badge_catalog.dart@2482+5: The value of the local variable 'known' isn't used.
  UNFORMATTED lib/features/badges/views/widgets/badge_celebrate_sheet.dart
  phases: overlay=0ms start=288ms diagnose=12594ms format=90ms
```

## Phase timings (step 3, not the official numbers)

Single in-process runs above use an in-memory byte store, so every run is
cold: `diagnose` is about 12.5 s on both scenarios. With an on-disk byte
store shared across runs (`--cache`), `s10`:

```
  phases: overlay=0ms start=285ms diagnose=14060ms format=95ms
  phases: overlay=0ms start=288ms diagnose=1740ms format=131ms
  phases: overlay=0ms start=285ms diagnose=1368ms format=132ms
```

The cache grows to 127 MB for this corpus.

## Observations for Task 4

- **No lint is reported.** `expected.md` lists `prefer_const_constructors`
  (s3, s10) and the pre-existing `directives_ordering`; the probe reports
  neither. The lint rule implementations ship with the SDK
  (`pkg/linter`), not with `package:analyzer` on pub.dev, and the
  `linter` package on pub.dev is discontinued at 1.30.1 (Dart 2). An
  embedded analyzer can only run lints it registers itself.
- **Diagnostic codes differ from the SDK.** The trap is reported as
  `undefined_instance_member_read`; `dart analyze` of Dart 3.13.4
  reports `undefined_method` for the same source (Task 4 compares with
  the corpus SDK).
- **`Diagnostic.severity` is not the reported severity.** It is a coarser
  enum; `diagnosticCode.severity` is the `DiagnosticSeverity` that
  `ErrorProcessor` replaces.

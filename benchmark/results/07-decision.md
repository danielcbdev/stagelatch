# Task 7: inputs to the decision

Recorded on 2026-11-18/19. Apple M4, macOS 27.2.1, corpus SDK Flutter 3.47.8 / Dart 3.13.7.

## Daemon simulation

`dart run benchmark/bin/daemon_sim.dart s3 --iterations 10`

```
initial analysis of the package: 27248 ms
iteration 0: 1128 ms (3 getErrors)
iteration 1: 1694 ms (3 getErrors)
iteration 2: 1730 ms (3 getErrors)
iteration 3: 1697 ms (3 getErrors)
iteration 4: 1660 ms (3 getErrors)
iteration 5: 1668 ms (3 getErrors)
iteration 6: 1661 ms (3 getErrors)
iteration 7: 1670 ms (3 getErrors)
iteration 8: 1694 ms (3 getErrors)
iteration 9: 1848 ms (3 getErrors)
p50 1694 ms, max 1848 ms
server resident memory: 3003 MB
```

`dart run benchmark/bin/daemon_sim.dart s10 --iterations 10`

```
initial analysis of the package: 26662 ms
iteration 0: 1295 ms (10 getErrors)
iteration 1: 1914 ms (10 getErrors)
iteration 2: 1921 ms (10 getErrors)
iteration 3: 1955 ms (10 getErrors)
iteration 4: 1838 ms (10 getErrors)
iteration 5: 1923 ms (10 getErrors)
iteration 6: 1856 ms (10 getErrors)
iteration 7: 1847 ms (10 getErrors)
iteration 8: 1856 ms (10 getErrors)
iteration 9: 1901 ms (10 getErrors)
p50 1901 ms, max 1955 ms
server resident memory: 3031 MB
```

## Formatting through the SDK CLI

The index content of the unformatted `s3` file piped to `dart --suppress-analytics format --stdin-name=lib/features/badges/views/widgets/badge_celebrate_sheet.dart`, run from the corpus root: the output equals the oracle's formatted text (`page_width: 120` honoured).

```
dart format --stdin-name, 10 runs: p50 20 ms, max 75 ms
```

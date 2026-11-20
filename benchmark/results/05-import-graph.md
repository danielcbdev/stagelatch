# Task 5: import graph

Recorded on 2026-11-18. Apple M4, macOS 27.2.1, Dart 3.13.4 (`dart run`,
JIT), `package:analyzer` 14.7.0.

Input: every `.dart` file of the corpus at the pinned SHA (`git ls-tree -r`,
2,462 files including the nested packages), read by blob id through one
`git cat-file --batch`: 193 to 280 ms.

Extractors:

- `directivesByParser`: `parseString(throwIfDiagnostics: false)`, then the
  URIs of `NamespaceDirective` (with each configuration), `PartDirective`
  and `PartOfDirective`.
- `directivesByScanner`: a hand-written scanner that skips whitespace,
  nested block comments, line comments, a script tag and annotations,
  collects string literals at parenthesis depth 0 inside each directive
  (concatenating adjacent ones) and stops at the first token that does
  not start a directive.

## Time per extractor, one fresh process each (step 2)

`dart run benchmark/bin/graph.dart parse` and `... scan`, three times each:

```
parseString: 1350 ms
parseString: 1331 ms
parseString: 1366 ms
scanner: 8 ms
scanner: 8 ms
scanner: 8 ms
```

The scanner is about 170 times faster: it reads only the top of each
file, the parser reads all of it.

## Agreement and dependents (steps 2 and 3)

`dart run benchmark/bin/graph.dart compare`:

```
files: 2462, read through cat-file --batch: 193 ms
parseString: 1353 ms
scanner: 6 ms
disagreeing files: 0
graph: 1415 imported files, built in 30.3 ms; dependents of lib/core/wallpaper/wallpaper_source.dart: 1705 files in 0.6 ms
```

The two extractors agree on all 2,462 files. The graph (edges from
relative and `package:Prism/` URIs, as `specs/dart-toolchain.md`
section 3 describes) is built in about 30 ms; the transitive dependents
of `lib/core/wallpaper/wallpaper_source.dart` (325 direct importers) are
1,705 files, found in 0.6 ms.

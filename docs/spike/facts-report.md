# Fact extractor: measurements for ADR-0017

Recorded on 2026-11-20 on an Apple M4 laptop, macOS, Dart 3.13.4 (`dart run`, JIT), `package:analyzer` 14.7.0.

Reproduce, after the setup of [`benchmark/README.md`](../../benchmark/README.md):

```bash
dart pub get --directory benchmark
cd benchmark
dart run bin/facts.dart sha          # SHA-256 against package:crypto
dart run bin/facts.dart edges        # hand-written edge cases, both extractors
dart run bin/facts.dart compare      # whole corpus, both extractors, every disagreement
dart run bin/facts.dart scan         # time of candidate S (run 3 times)
dart run bin/facts.dart parse        # time of candidate P (run 3 times)
dart run bin/facts.dart adversarial  # list the hostile inputs
dart run bin/facts.dart adversarial 3 parse   # one input, one extractor (use `timeout`)
dart run bin/facts.dart fuzz         # broken variants of corpus files
```

## What is compared

Corpus: Hash-Studios/Prism at the pinned SHA of [`corpus.yaml`](../../benchmark/corpus.yaml), every `.dart` file read by blob id through one `git cat-file --batch`: **2,462 files**.

Both candidates produce the same facts, in the same shape ([`facts_model.dart`](../../benchmark/lib/facts_model.dart)):

- `annotatedDeclarations`: top-level declarations, class, mixin, extension and extension-type members, and enum constants, that carry at least one annotation other than `override`, `protected`, `visibleForTesting`, `immutable`, `Deprecated` and `deprecated`. Name, annotation names (as written, sorted), SHA-256 of the token lexemes joined by one space, line and column of the first `@`.
- `testCalls`: unqualified calls to `test`, `testWidgets` and `group`. Function, description (the literal's value, or the argument's source text), enclosing `group` descriptions, the location of a `solo` argument other than `false`, the location of a `skip` argument other than `false` and `null` (or of a `@Skip` annotation on the enclosing top-level function or on the library), and the location of the call.
- `identifiers`: every identifier and keyword token of the file.

The candidates:

- **P**, the reference: [`facts_parse.dart`](../../benchmark/lib/facts_parse.dart). `parseString(throwIfDiagnostics: false)` for the AST, and the analyzer's own scanner (`scanString`) for the token stream the hash is defined on. It lives in `benchmark/` only.
- **S**: [`facts_scanner.dart`](../../benchmark/lib/facts_scanner.dart). One lexing pass (strings with nested interpolation through an explicit stack, nested block comments, numbers with digit separators, longest-match operators), then recognizers over the token list. No recursion on the input. SHA-256 is [`sha256.dart`](../../benchmark/lib/sha256.dart), 77 lines, because the Dart core libraries have no hash and `package:crypto` would be a new runtime dependency.

## Agreement

| Input | Result |
|---|---|
| Corpus, 2,462 files | **0 files disagree.** 2,012 annotated declarations, 11,148 test calls, and the identifier set of every file are identical. |
| 12 hand-written edge cases (below) | 0 disagree |
| SHA-256 against `package:crypto`, 10 inputs including 55, 56, 63, 64 and 65 bytes (the padding boundaries), UTF-8 text and 100,000 bytes | 10 of 10 equal |

The edge cases: an interpolated description (`'adds $n'`, `'${n + 1}'`); `solo: true`, `solo: false`, `skip: true`, `skip: false`, `skip: null`, `skip: 'reason'`, `skip: someFlag`; nested groups; `@Skip` on the library; `@Skip` on a function; a method call `obj.test('x')`, a named argument `test: 1` and a declaration `void test(...)`, none of which is a test call; adjacent, escaped, raw and multi-line string descriptions; `@JsonSerializable` with a factory, a field and an `@override`; `@freezed` with a redirecting factory and an annotated parameter, and an enum with annotated constants and a getter; a constructor whose initializer list has braces; annotated variables and functions with other annotations stacked; generics closing with `>>` and operators.

**How S got there**, so the numbers are not read as a first-try result. The first full comparison had 47 disagreeing files, all from three lexer or recognizer gaps, each fixed once and then covered by the corpus:

1. A method with type parameters (`TResult map<TResult extends Object?>(...)`): the name is before the `<`, not before the `(`. Most of the 47 were generated `*.freezed.dart` files.
2. Digit separators (`1_900_000_000_000`): one number token, not a number followed by an identifier.
3. `[]` and `[]=` are single tokens in the Dart scanner (`operator []=`).

## Time

Fresh process each, `dart run` (JIT), three runs, in milliseconds.

| | S | P | P / S |
|---|---|---|---|
| 10 files of scenario s10, cold (first calls of the process) | 8.5, 8.6, 8.6 | 131, 133, 134 | 15x |
| All 2,462 files | 426, 428, 430 | 2,429, 2,433, 2,434 | 5.7x |

Start-up cost of carrying the analyzer, measured as `dart <program>.dill` of a program that extracts the facts of a three-line file, six runs each:

| | Kernel size | Process time |
|---|---|---|
| S only | 8.7 MB | 0.08 to 0.11 s |
| With `package:analyzer` | 36.8 MB | 0.16 s |

The 0.1.0 README measures the activated executable at 0.78 s (s3) and 0.92 s (s10) for `format`, `pubspec` and `sensitive-files`, warm p50. The new `pre-commit` checks read the facts of the changed `.dart` files and, for `codegen` and `tests`, of their base versions: at most 3 and 10 files, twice. Estimated from the table, not measured through the CLI (that is plan 03 Task 10):

| | s3 | s10 |
|---|---|---|
| S: facts of 6 and 20 file versions, at about 0.85 ms each | +5 ms | +17 ms |
| P: start-up 0.08 s, plus 6 and 20 file versions at about 13 ms each | +0.16 s | +0.34 s |

Both fit under 2 s (P would bring s10 to about 1.3 s), so the budget does not separate the candidates; the margin does.

## Adversarial input (S6)

Each input is 1 MiB, one process per extractor and input, 60 s limit (120 s for the three that exceeded it).

| Input | S | P |
|---|---|---|
| `(` repeated | 97 ms | **no answer in 120 s** |
| `{` repeated | 112 ms | **no answer in 120 s** |
| `[` repeated | 117 ms | **no answer in 120 s** |
| `'${` repeated (nested interpolation) | 70 ms | **Stack Overflow** after 16 ms |
| `/*` repeated (nested comments) | 7 ms | 38 ms |
| Unterminated string | 5 ms | 50 ms |
| One identifier | 10 ms | 57 ms |
| `@a ` repeated | 74 ms | 192 ms |
| `test(` repeated | 51 ms | **Stack Overflow** after 91 ms |
| `group('a', () {` repeated | 50 ms | 31 s |
| `class A { @a int x; ` repeated | 49 ms | 7.4 s |
| `A() : x = ` repeated | 53 ms | 955 ms |

S is linear on all twelve. `parseString` throws a `StackOverflowError` on two and does not return on three, which on a hook would hang a commit. A committed file is untrusted input (security rule S6); P would need a size or nesting guard in front of it, which S does not.

## Broken input

Fuzz: 400 corpus files, each turned into up to four broken variants (cut at a random point, one `}` removed, one `)` removed, one stray `'` inserted): 1,558 variants.

| | |
|---|---|
| S threw | 0 |
| `parseString` reports syntax errors | 1,459 |
| S's lexical check (unterminated string or block comment, brackets that do not pair) flags | 1,432, all of them among the 1,459 (98.1%) |

The remaining 27 are errors a lexer cannot see (for example a removed `)` that leaves the brackets paired by luck). S does not claim to detect syntax errors; it detects the ones that would make its own answer meaningless.

On the **valid** corpus, `parseString` reports syntax errors in **30 of 2,462 files**, all generated `*.freezed.dart` files, with `extraneous_modifier: Can't have modifier 'final' here`. The app is on a newer language version than the embedded `analyzer` 14.7.0 can parse. The scanner flags none of them, and the facts of both agree on all 30. This is the version coupling of candidate P, observed.

## Size

| | Lines |
|---|---|
| S: lexer (`lex` and `_punctLength`, about 290) and recognizers (about 570, including string decoding and the call and declaration heuristics) | 939 as a throwaway prototype, `dart format`ed |
| P: the reference | 273 |
| SHA-256 | 77 |

P is shorter because the parser does the work, and it brings `package:analyzer` 14.7.0 (36.8 MB of kernel in the measurement above) into the activated tool's dependency graph.

## Known limits of S

Heuristics that a parser does not need, none of which showed up in the corpus or the edge cases:

- **Where a declaration ends** is the first `;`, or the `}` that closes its body, with two refinements: after a depth-0 `=` or `=>` a `{` is an expression, and after a depth-0 `:` (constructor initializer list) a `{` is an expression unless the token before it is `)`, `}` or a word other than `const` and `new`. An initializer list that ends in a bare identifier followed by a map literal body would be misread.
- **Whether `test(` is a call** is decided by the token before it (a statement or expression boundary, or `await`, `return`, `yield`, `throw`, `else`, `do`). `int? test(...)` is taken for a declaration, which is right, and `a ? test(1) : 2` for a call, which is right.
- **Not covered:** a call with explicit type arguments (`testWidgets<T>(`); primary-constructor class headers (`class C(final int x);`), which the embedded analyzer also rejects (the 30 files above).
- **Language growth:** a new operator or literal form is a lexer change (the digit separators were one); a new declaration form is a recognizer change.

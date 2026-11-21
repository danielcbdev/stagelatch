# Writing a custom check

Custom checks let a team add project-specific rules without putting
stagelatch on the project's dependency graph. Each check is a separate
process that speaks **protocol 1** (line-delimited JSON on stdin/stdout).
There is no `stagelatch_core` package in 1.0.0: copy the reference under
[`example/custom_check/`](../example/custom_check/) and follow this guide.

The normative contract is [`specs/custom-checks.md`](specs/custom-checks.md).

## 1. Write a rule

Keep rule logic in a small library you can unit-test. The example's
`example/no-print` rule lives in `lib/no_print.dart` and looks for
`print(` in source text:

```dart
final RegExp printCallPattern = RegExp(r'\bprint\s*\(');

({int line, int column})? findPrintCall(String source) {
  final match = printCallPattern.firstMatch(source);
  if (match == null) return null;
  // ... turn match.start into 1-based line/column
}
```

The process entry point (`bin/check.dart`) only speaks the protocol:

1. On `init` → reply with `ready` listing every rule id as
   `<check>/<rule>` (here `example/no-print`).
2. On `run` → for each changed `.dart` path, send `read` with
   `side: "snapshot"`, inspect the `content` text, emit zero or more
   `finding` messages, then `done`.

Content you analyze must come from `read`. Do not open the working tree
for source under review; the host serves the **snapshot**.

## 2. Test it

Unit-test the pure rule:

```bash
cd example/custom_check
dart pub get
dart test
```

Then exercise the peer through stagelatch against a real repository
(see the acceptance scenario AC-34). A well-behaved check completes
`init` → `ready` → `run` → optional `finding` → `done` without protocol
errors.

## 3. Wire it in config

In `stagelatch.yaml`:

```yaml
hooks:
  # Custom checks are not on the default pre-commit list (spawn cost).
  pre-push: [analyze, tests/affected, example]
  # ci defaults to the union of pre-commit and pre-push when omitted.

custom_checks:
  example:
    run: [dart, run, example/custom_check/bin/check.dart]
    # timeout: 60s
    sources:
      - example/custom_check/bin/check.dart
      - example/custom_check/lib/no_print.dart
      - example/custom_check/pubspec.yaml
    rules:
      no-print: error
```

Notes:

- The map key (`example`) is the check id. Rule ids are `example/no-print`.
- Prefer `run: [dart, run, <path-to-.dart>]` so the host can infer a
  single entry when the check is one file. For a multi-file package,
  set `sources` to the files that must match the snapshot (exit 78 if
  the closure would be empty).
- Put the check id (or a rule id) on the hook lists that should run it.
  Declaring `custom_checks:` alone does not schedule anything.
- Opt into `pre-commit` only if you accept the extra latency.

Severity may also be set under the root `rules:` map
(`example/no-print: warning`). Use `stagelatch:ignore example/no-print`
on the finding line or the line above, same as built-in rules.

## 4. Skip custom checks (`--no-custom-checks`)

`stagelatch run` and `stagelatch ci` accept `--no-custom-checks`. When
set, no custom-check child starts, selectors that name only custom
checks are skipped, and the notice
`Skipping custom checks (--no-custom-checks).` is written to stderr
(and to JSON `notices`).

Use it for **pull requests from forks** (or any CI that must not execute
untrusted check code from the branch), and when local check sources
diverge from the snapshot and you need a temporary escape hatch. Prefer
staging or committing the check sources so the gate stays green without
the flag.

## 5. Next steps

- Protocol messages and adversarial limits:
  [`specs/custom-checks.md`](specs/custom-checks.md) §§10–11.
- Source divergence and exit codes: same spec §§6 and 16.
- Reference implementation: [`example/custom_check/`](../example/custom_check/).

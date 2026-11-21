# Example custom check

Minimal Dart peer that speaks stagelatch **protocol 1**. It declares
`example/no-print` and reports `print(` calls in changed `.dart` files.

This is not a published package. Copy the pattern into your repository
(for example under `tool/`), or point `custom_checks` at this tree while
experimenting.

## Try it

```bash
cd example/custom_check
dart pub get
dart test
```

Wire it from the repository root (see [`docs/custom-checks.md`](../../docs/custom-checks.md)):

```yaml
hooks:
  pre-push: [example]

custom_checks:
  example:
    run: [dart, run, example/custom_check/bin/check.dart]
    sources:
      - example/custom_check/bin/check.dart
      - example/custom_check/lib/no_print.dart
      - example/custom_check/pubspec.yaml
    rules:
      no-print: error
```

Then:

```bash
stagelatch run pre-push
```

Use `stagelatch run pre-push --no-custom-checks` (or the same flag on
`stagelatch ci`) when you must skip custom checks — for example on pull
requests from forks.

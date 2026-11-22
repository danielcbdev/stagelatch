# stagelatch examples

stagelatch is a command-line tool, so its examples are a configuration file
and a custom check rather than Dart code that imports the package.

## Install and run

```bash
dart pub global activate stagelatch

cd your_flutter_project
stagelatch init               # detects the stack, writes stagelatch.yaml, installs hooks
stagelatch run pre-commit     # what the git hook runs
stagelatch ci --base origin/main --reporter github
```

## Minimal `stagelatch.yaml`

```yaml
min_version: 1.0.0

hooks:
  pre-commit: [format, pubspec, sensitive-files]
  pre-push: [analyze]

# Severity per rule: error | warning | off.
rules:
  pubspec/unpinned-git: off

# Paths that never produce findings.
exclude: [lib/generated/**]
```

Every key, default and validation is described in the
[configuration reference](https://github.com/danielcbdev/stagelatch/blob/main/docs/specs/config.md).

## Custom check

[`custom_check/`](custom_check/) is a small Dart program that speaks the
stagelatch custom check protocol (version 1). It declares the rule
`example/no-print` and reports `print(` calls in changed `.dart` files.

It is not a published package: copy the pattern into your repository (for
example under `tool/`) and wire it with `custom_checks:` in `stagelatch.yaml`.
See [`custom_check/README.md`](custom_check/README.md) for the exact
configuration and for how to run its tests.

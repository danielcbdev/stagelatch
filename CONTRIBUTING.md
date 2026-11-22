# Contributing to stagelatch

Thanks for taking the time. Bug reports, edge cases and focused fixes are all welcome.

- **Security problems:** do not open an issue. Follow [`SECURITY.md`](SECURITY.md).
- **Conduct:** this project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- For anything larger than a small fix, open an issue first so the approach can be agreed before you write code.
- The `1.x` line has a stability contract ([`docs/stability.md`](docs/stability.md)): config keys, rule IDs, exit codes, report shapes, the custom-check protocol, the baseline format and the managed hook script. A change that breaks any of them is a major version and needs a `!` commit and a migration note.
- The decisions behind the design are recorded as ADRs in [`docs/adr/`](docs/adr/README.md). If a change touches one, read it first; if it contradicts one, the ADR changes in the same pull request or the change does not land.

## Set up

You need a Dart SDK that satisfies `^3.13.0` and git.

```bash
dart pub get
```

```bash
dart pub get --directory benchmark && dart pub get --directory example/custom_check
```

The second command resolves the nested packages that the root analysis and formatting also cover.

## Check your change

CI runs exactly these, so run them before you push:

```bash
dart format --output=none --set-exit-if-changed .
```

```bash
dart analyze --fatal-infos
```

```bash
dart test --coverage-path=coverage/lcov.info
```

```bash
dart run tool/check_coverage.dart
```

The formatter check is authoritative on the stable SDK only, because formatter output is specific to an SDK release ([ADR-0008](docs/adr/0008-parity-with-the-project-sdk.md)).

Behaviour that depends on git is covered by acceptance tests that build real repositories in a temporary directory. A new rule or a changed edge case needs one. [`docs/engineering/testing.md`](docs/engineering/testing.md) explains the layers and the mandatory scenarios.

## Branches and pull requests

- Branch from `develop`: `<type>/<short-slug>`, where the type is a Conventional Commits type (`feat`, `fix`, `docs`, `test`, `refactor`, `ci`, `chore`).
- Open the pull request against `develop`. `main` only receives release pull requests.
- The pull request title is the changelog entry, in Conventional Commits form: `<type>(<scope>): <summary>`, imperative, lowercase start, no period.
- Pull requests are squash-merged, and every CI job must be green. The `dogfood` job runs stagelatch on its own pull request.
- Fill in the pull request template, including the two review checklists.

The complete flow, with scopes and the release process, is in [`docs/engineering/workflow.md`](docs/engineering/workflow.md). It was written for the coding agents that built the project, so read it as the full reference rather than a requirement: the list above is what a human contributor needs.

## Code standards

- Lints are `very_good_analysis` with `strict-casts`, `strict-inference` and `strict-raw-types`. Zero warnings.
- Code, comments, commit messages, docs and CLI output are in English. Console output is ASCII only.
- The five-module layout (`domain`, `checks`, `application`, `infrastructure`, `cli`) is enforced by an architecture test: `dart:io` lives only in `infrastructure` and `cli`.
- Verdicts stay deterministic: no network, no clock- or machine-dependent behaviour, no AI in the blocking path.

The full list, including the review checklist, is in [`docs/engineering/coding-standards.md`](docs/engineering/coding-standards.md) and [`docs/engineering/security.md`](docs/engineering/security.md).

## Writing a custom check

If what you need is a rule specific to your own project, you may not need to change stagelatch at all: [custom checks](docs/custom-checks.md) run out of process and have a reference implementation in [`example/custom_check/`](example/custom_check/).

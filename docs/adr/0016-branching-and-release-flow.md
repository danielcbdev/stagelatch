# ADR-0016: Branching and release flow

- Status: Accepted
- Date: 2026-11-11

## Context

Implementation is done by an agent, task by task. Some required scenarios (the Windows hook, the three-OS matrix) can only be verified by CI, not on the developer's machine. Releases must follow Conventional Commits and `release-please`.

## Decision

- `main` holds released code only. `develop` is the integration branch.
- One short-lived branch per plan task, cut from `develop`: `<type>/<plan>-<task>-<slug>`, for example `feat/01-05-cat-file-batch`.
- A task is merged through a pull request into `develop`, **squash-merged**, with a Conventional Commits title. The agent merges its own pull request only when every required CI job is green.
- A release is a pull request from `develop` into `main`, merged with a **merge commit** so `release-please` sees each squashed commit. After the release, `main` is merged back into `develop`.
- No direct pushes to `main` or `develop`. No force-push to shared branches.

## Consequences

- Every task gets a CI run on Ubuntu, macOS and Windows before it lands.
- History on `develop` is one commit per task, which maps one-to-one to plan checkboxes.
- Branch protection on `main` and `develop` (required checks, no direct push) must be configured once by the owner; the agent cannot do it without admin rights.

## Alternatives rejected

- **Local merges into `develop` without pull requests:** skips the only place Windows is tested.
- **Trunk-based on `main`:** conflicts with the owner's request for a `develop` integration branch.

Details: [`engineering/workflow.md`](../engineering/workflow.md).

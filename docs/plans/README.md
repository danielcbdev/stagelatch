# Implementation plans

Status: **Approved (2026-11-12).** Plans are executed in order, one task at a time, following [`engineering/workflow.md`](../engineering/workflow.md).

| Plan | Delivers | Depends on | Status |
|---|---|---|---|
| [`00-spike.md`](00-spike.md) | Measurements; mechanism of ADR-0008 | nothing | not started |
| [`01-foundation.md`](01-foundation.md) | `0.1.0-dev.1` | nothing | release pending |
| [`02-core.md`](02-core.md) | `0.1.0` | 01, and the approved spike report | not started |
| [`03-checks.md`](03-checks.md) | `0.2.0` | 02 | not started |
| [`04-affected.md`](04-affected.md) | `0.3.0` | 03 | not started |
| [`05-public-api.md`](05-public-api.md) | `1.0.0` | 04, and re-approval of the custom-checks spec | draft |

Plans 00 and 01 share no files and may run in either order. Everything else is strictly sequential.

## How to read a task

Every task has the same parts:

- **Branch:** the branch name to create from `develop`.
- **Files:** exact paths to create or modify.
- **Interfaces:** `Consumes` (what the task uses from earlier tasks) and `Produces` (what later tasks rely on). Signatures here are binding; [`architecture.md`](../architecture.md) holds the canonical ones.
- **Steps:** checkboxes. Tick each one in the pull request that completes it.

Steps follow one cycle:

1. **Write the failing tests.** The task gives test names and the assertions that carry spec values. Write them exactly; add more where the spec section cited by the task lists a case the task does not.
2. **Run and see them fail** for the stated reason. A test that passes before the code exists is wrong.
3. **Implement.** The task gives signatures and the decisions you cannot infer. You write the bodies, with doc comments as required by [`coding-standards.md`](../engineering/coding-standards.md#7-comments).
4. **Run everything:** the four commands of [`testing.md`](../engineering/testing.md#7-commands).
5. **Commit and open the pull request** with the given title.

## Rules for the implementer

- A plan does not repeat the spec. Read the cited spec section before writing the test.
- If a signature you need is missing, add it to `architecture.md` in the same pull request and list it under "Deviations".
- If the plan and a spec disagree, the spec wins; fix the plan in the same pull request.
- Do not start a task whose `Consumes` block names something that is not merged.
- Do not batch tasks into one pull request.

## Keeping this table current

When the last task of a plan merges, change its status here to `done (<version>)` in the release pull request.

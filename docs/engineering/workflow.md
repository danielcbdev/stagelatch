# Development workflow

Status: **Approved (2026-11-12).** This is the loop an implementing agent follows. Decision record: ADR-0016.

## 1. Branches

| Branch | Purpose | Who writes |
|---|---|---|
| `main` | Released code. Tags come from here. | Release pull requests only |
| `develop` | Integration. Always green. | Squash-merged task pull requests only |
| `<type>/<plan>-<task>-<slug>` | One plan task | The agent |

- `<type>` is the Conventional Commits type of the task: `feat`, `fix`, `refactor`, `test`, `docs`, `build`, `ci`, `chore`.
- `<plan>` and `<task>` are the two-digit numbers from the plan: `feat/01-05-cat-file-batch`.
- The spike uses `spike/00-<task>-<slug>`.
- A task branch lives for one task and is deleted after merge.

## 2. The task loop

For each unchecked task in the current plan, in order:

1. **Sync.** `git switch develop && git pull --ff-only`.
2. **Branch.** `git switch -c <type>/<plan>-<task>-<slug>`.
3. **Read.** The task, the spec sections it cites, and the `Interfaces` blocks of the tasks it consumes.
4. **Implement** step by step exactly as the task lists: failing test, see it fail, code, see it pass.
5. **Verify locally.** All four commands in [`testing.md`](testing.md#7-commands) pass.
6. **Self-review** against the checklists in [`coding-standards.md`](coding-standards.md#10-review-checklist) and [`security.md`](security.md#security-checklist-for-every-pull-request).
7. **Tick the checkboxes** of the task in the plan file, in the same branch.
8. **Push and open a pull request** into `develop` (template below).
9. **Wait for CI.** Every required job must be green. Fix failures on the branch; never merge red, never retry a job hoping it passes.
10. **Squash-merge**, delete the branch, go back to step 1.

```bash
gh pr create --base develop --title "<conventional title>" --body-file <file>
```

```bash
gh pr merge --squash --delete-branch
```

A task is **one** pull request. If a task turns out to need two, stop and split it in the plan first.

## 3. Commits and pull request titles

- Conventional Commits: `<type>(<scope>): <summary>`.
- Scopes: `domain`, `checks`, `pipeline`, `config`, `git`, `dart`, `reporters`, `hooks`, `cli`, `ci`, `release`, `docs`.
- Summary in the imperative, lowercase start, no period, at most 72 characters.
- The squash commit takes the pull request title; write the title as the changelog entry you want.
- A breaking change uses `!` and a `BREAKING CHANGE:` footer.
- Commits inside a task branch follow the same format; each plan step that says "commit" is one commit.

## 4. Pull request description

```markdown
## What
One or two sentences.

## Plan task
docs/plans/<file>.md, Task N

## How it was verified
- [ ] dart format, dart analyze --fatal-infos, dart test, coverage check
- Acceptance scenarios added or touched: AC-..

## Checklists
- [ ] Coding standards review checklist
- [ ] Security checklist

## Deviations from the plan
None, or each one with the reason.
```

## 5. Definition of done for a task

- Every step of the task is ticked and every test it names exists and passes.
- The four verification commands pass locally and in CI on all matrix cells.
- Public members have doc comments; user-facing strings match the spec exactly.
- No unrelated change is included.
- The plan file is updated; if a spec or the architecture had to change, that change is in the same pull request and is listed under "Deviations".

## 6. When to stop and ask the owner

Stop work, leave the branch as it is, and ask, when:

- a spec contradicts `CLAUDE.md`, an ADR or another spec;
- a fixed decision looks wrong in practice;
- the task needs a runtime dependency that is not on the allowlist;
- a mandatory acceptance scenario cannot be made to pass;
- a gate fails: the spike's latency or parity criteria, or the coverage floor;
- something needs credentials or admin rights: branch protection, repository secrets, the first pub.dev publish, enabling automated publishing;
- the only way forward is a destructive git operation on a shared branch.

Do not ask about things a spec already decides, and do not work around a gate.

## 7. Plan gates

- **After plan 00 (spike):** the owner approves the spike report and the ADR-0008 amendment before plan 02 starts. Plan 01 does not depend on the spike and may run in parallel.
- **After each release plan:** the release pull request into `main` is opened by the agent and merged by the owner.
- **Before plan 05:** the draft custom-checks spec is re-approved.

## 8. Releases

1. All tasks of the plan are merged into `develop` and CI is green.
2. Open a pull request `develop` -> `main` titled `release: <version>`. Merge with a **merge commit**.
3. `release-please` opens its release pull request on `main` with the version bump and CHANGELOG. The owner merges it; the tag triggers the publish workflow (OIDC).
4. Merge `main` back into `develop` through a pull request titled `chore(release): sync main into develop`.

The first publish of the package name to pub.dev is done manually by the owner; automated publishing can be enabled only for a package that already exists.

## 9. One-time repository setup (owner)

- Protect `main` and `develop`: require the CI checks, require pull requests, forbid force pushes.
- Enable "Allow squash merging" and "Allow merge commits"; disable rebase merging.
- Enable private vulnerability reporting.
- After the first manual publish: enable automated publishing on pub.dev for the repository and the tag pattern `v{{version}}`.

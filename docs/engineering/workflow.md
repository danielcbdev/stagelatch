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
- After `1.0.0`, a change that breaks any artefact in [`stability.md`](../stability.md) §1 (config keys/types/rejects/exit 78, rule ids, exit codes, JSON/SARIF/JUnit shapes, custom-check protocol 1, baseline format, managed hook contract) **must** be a major: use `feat!` / `fix!` (or another type with `!`) and a `BREAKING CHANGE:` footer that names the §1 artefact and points at a migration note in the CHANGELOG. Compatibility tests under `test/compat/1.0/` stay; a new major adds `test/compat/<major>.0/` alongside them.
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
2. Open a pull request `develop` -> `main` titled `release: <version>`. Merge with a **merge commit**, never squash: release-please reads the Conventional Commits that reach `main`, and a squash leaves it a single `release:` commit, which is not user facing, so it opens no release pull request.
3. `release-please` opens its release pull request on `main` with the version bump and CHANGELOG. A pull request opened with `GITHUB_TOKEN` starts no CI run; close and reopen it (or push an empty commit to its branch) so the checks run, then the owner reviews the version and CHANGELOG and merges it (see "Merging the release-please pull request" below). release-please then creates the tag and the GitHub release, and its workflow dispatches `publish.yaml` on that tag, which publishes through OIDC (see "How the tag reaches the publish workflow" below).
4. Merge `main` back into `develop` through a pull request titled `chore(release): sync main into develop`, with a **merge commit**, so `main` stays an ancestor of `develop`.

### CHANGELOG hygiene (do not hand-edit the bot branch)

- **Never edit `CHANGELOG.md` (or the version bump) by hand on the release-please branch.** If generation is wrong, fix the cause on `develop` (commit messages, the develop→main merge method, or a mistaken `BEGIN_COMMIT_OVERRIDE`), then re-run the `release-please` workflow so it regenerates the pull request. Hand-editing hides the bug and races the next bot update.
- On the `release: <version>` branch, avoid commits that exist only there (for example marking the plan done). Prefer those on `develop` first, so every commit that reaches `main` already has its own associated pull request. Commits whose only associated PR is the release PR inherit that PR's body for changelog parsing ([`preprocessCommitMessage` in release-please](https://github.com/googleapis/release-please/blob/v17.6.0/src/commit.ts)).

### `BEGIN_COMMIT_OVERRIDE` — recovery for a squashed release only

If the release pull request into `main` was squashed anyway, add a `BEGIN_COMMIT_OVERRIDE` ... `END_COMMIT_OVERRIDE` block to its description, one Conventional Commit per line, and re-run the `release-please` workflow run of that merge. release-please reads the block in place of the squash commit's message ([How can I fix release notes?](https://github.com/googleapis/release-please#how-can-i-fix-release-notes)). This is how `0.1.0` was released (#49) and how `0.2.0` was released (#67).

Rules when using the override:

- Use it **only** on a squash-merged release PR. Upstream documents that the feature does not work with plain merges, because release-please cannot tell which commit(s) to apply it to. In practice, with a merge commit it still attaches the associated PR body to every commit whose `associatedPullRequests[0]` is that release PR (the merge commit plus any commits authored only on the release branch), and replaces each of those messages with the override ([`preprocessCommitMessage`](https://github.com/googleapis/release-please/blob/v17.6.0/src/commit.ts); GraphQL association in [`github.ts`](https://github.com/googleapis/release-please/blob/v17.6.0/src/github.ts)). That is what duplicated `feat(cache): … (#73)` four times for `0.3.0` (#83 merge commit + `bd7b311` + `141fe2e` + the real `#73` squash), after a `### END_COMMIT_OVERRIDE` markdown heading left only the first override line parseable.
- Do **not** put `BEGIN_COMMIT_OVERRIDE` on a correctly merge-committed `release: <version>` PR. The Conventional Commits on the merged history are already enough.
- Write the markers as plain lines (`BEGIN_COMMIT_OVERRIDE` / `END_COMMIT_OVERRIDE`), never as Markdown headings (`### …`). A leftover `###` after the split breaks expansion of the following conventional lines.
- Separate override entries with a **blank line** so `splitMessages` can split them ([`commit.ts`](https://github.com/googleapis/release-please/blob/v17.6.0/src/commit.ts)); single newlines alone are fragile.

### Merging the release-please pull request

Upstream accepts both squash-merge and merge commits for the release-please PR itself ([What's a Release PR?](https://github.com/googleapis/release-please#whats-a-release-pr)). For this repository:

- Prefer **squash-merge** of `chore(main): release <version>` so the version bump is one commit on `main`.
- A merge commit is also fine if the branch tip is a single bot commit with no hand fixes.
- Do not push fixup commits onto the bot branch. If CI fails or the CHANGELOG is wrong, fix via `develop` (or the develop→main process above), not on `release-please--branches--main--components--stagelatch`.

`include-component-in-tag: false` in `release-please-config.json`: by default release-please prefixes tags with the pubspec name (`stagelatch-v0.1.0`). Tags must be `v<version>`, the pattern `publish.yaml` triggers on and the one pub.dev's automated publishing is configured with.

From `0.1.0`, a `feat` bumps to `0.2.0` and a `fix` to `0.1.1`. When a plan targets another version, set `"release-as": "<version>"` on the `.` package before the release pull request into `main`, and remove it after release-please's pull request is merged.

When the current version is a pre-release (`0.1.0-dev.1`), release-please's Dart updater writes the new pubspec version with the old suffix as build metadata (`0.1.0+-dev.1`). Check the `version:` line of the release pull request and fix it on its branch before merging; `test/version_test.dart` fails while it differs from `lib/src/version.dart`.

The first publish of the package name to pub.dev was done manually by the owner (`0.1.0-dev.1`), because automated publishing can be enabled only for a package that already exists. That release has no tag; release-please anchors on `v0.1.0` and later tags.

### How the tag reaches the publish workflow

release-please pushes the tag with the workflow's default `GITHUB_TOKEN`, and GitHub does not start workflow runs for events caused by that token, except `workflow_dispatch` and `repository_dispatch` ([Triggering a workflow from a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)). A `push: tags` trigger alone would therefore never publish a release made by release-please.

So `release-please.yaml` has a second job: when `release_created` is true, it runs `gh workflow run publish.yaml --ref <tag>` with `actions: write` and nothing else. `publish.yaml` accepts `workflow_dispatch`. The dispatched run's OIDC token carries the tag as its ref (`refType: tag`), which is what pub.dev checks; pub.dev accepts `push` and `workflow_dispatch` events, each only when enabled on the package's admin page ([automated publishing](https://dart.dev/tools/pub/automated-publishing); the check is in `app/lib/package/backend.dart` of dart-lang/pub-dev). No secret is stored.

**Owner step on pub.dev, once, before the first automated release:** on the stagelatch admin page, under automated publishing, also tick **Enable publishing from `workflow_dispatch` events**, keeping the push event and the tag pattern `v{{version}}`. Without it pub.dev refuses the dispatched run.

A tag pushed by a person still publishes through the `push` trigger.

## 9. One-time repository setup (owner)

- Protect `main` and `develop`: require the CI checks, require pull requests, forbid force pushes.
- Enable "Allow squash merging" and "Allow merge commits"; disable rebase merging.
- Enable private vulnerability reporting.
- Under Settings > Actions > General > Workflow permissions, tick "Allow GitHub Actions to create and approve pull requests"; release-please cannot open its release pull request without it.
- After the first manual publish: enable automated publishing on pub.dev for the repository and the tag pattern `v{{version}}`, with both the push and the `workflow_dispatch` events.

# ADR-0006: Thin hook scripts that never block when the tool is missing

- Status: Accepted
- Date: 2026-11-11

## Context

Hook scripts live in each clone and cannot be updated centrally. Logic placed there is logic that goes stale. A hook that fails because the tool is not installed turns a new contributor's first commit into a setup problem.

## Decision

- The hook script only locates the executable and `exec`s it. Its exact text is in [`specs/git.md`](../specs/git.md#hook-script).
- Lookup order: `stagelatch`, then `stagelatch.bat`, then `dart pub global run stagelatch` when `dart pub global list` shows the package.
- When nothing is found, the hook prints one line to stderr and exits 0.
- Every generated script contains the marker line `# stagelatch:managed`. Only files with that marker are ever overwritten or removed without `--force`.
- Scripts are written with LF line endings on every platform.

## Consequences

- Behavior changes ship with the tool, not with the hook.
- The two fallbacks exist for Git for Windows, whose `sh` may not resolve the `.bat` shim that pub generates. The final form is whatever passes the Windows acceptance test.
- A missing install is silent in the verdict. That is acceptable only because CI is the guarantee (ADR-0005).

## Alternatives rejected

- **Fail when the tool is missing:** blocks contributors who have not set up yet.
- **Embed check logic in shell:** unmaintainable and untestable across platforms.

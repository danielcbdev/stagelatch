# ADR-0002: Safe autofix through the index

- Status: Accepted
- Date: 2026-11-11

## Context

Formatting can be fixed automatically, but the fix must land in the commit. Rewriting the file on disk and re-adding it would stage the developer's unstaged changes too.

## Decision

- A fix is the full new text of one snapshot file.
- The fixed blob is written with `git hash-object -w --stdin --no-filters` and placed in the index with `git update-index --index-info`, keeping the entry's mode.
- The working tree copy is refreshed **only** when the file had no unstaged changes before the fix. The refresh is done by `git checkout-index --force`, so git applies line-ending and filter configuration.
- Whether a file had unstaged changes is measured before any index write.
- Fixes are applied only when the snapshot is the index. Commit snapshots (pre-push, CI) are immutable; there the same check reports a finding.

## Consequences

- With partial staging, the commit is formatted and the developer's unstaged edits are untouched. The working tree file then differs from the index by formatting plus those edits, which is correct.
- A held `index.lock` makes the fix fail; the run ends with exit 70 and a message naming the lock.
- Acceptance tests must cover: clean file, partially staged file, CRLF working tree with `core.autocrlf`, executable mode preserved.

## Alternatives rejected

- **Format on disk and `git add`:** stages unrelated unstaged hunks.
- **Report only, never fix:** a formatter that only complains is the main reason people bypass hooks.

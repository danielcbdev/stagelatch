# Git integration specification

Status: **Approved (2026-11-12).** Everything the tool does with git. Security rules S1, S3, S4, S11 and S12 apply to all of it.

## 1. Requirements and conventions

- Git 2.30 or newer. `doctor` fails below that.
- Every invocation is `git <args>` with an argument list, the tool's working directory, and the inherited environment (so `GIT_INDEX_FILE`, `GIT_DIR` and `GIT_WORK_TREE` set by git during a hook are honored).
- Every command that prints paths uses `-z`. Output is decoded as UTF-8; a path that is not valid UTF-8 is a usage error naming the raw bytes in hexadecimal.
- A git command that exits non-zero where the spec does not expect it raises `InternalException` with the command and its stderr.
- A bare repository, or running outside a work tree, is a usage error.

## 2. Repository layout

`GitRepository.layout()` runs one command:

```
git rev-parse --show-toplevel --git-dir --git-common-dir --git-path hooks --is-shallow-repository
```

- `--git-path hooks` already accounts for `core.hooksPath` and for linked worktrees.
- Current branch: `git symbolic-ref --quiet --short HEAD`; a detached `HEAD` gives no branch.
- Merge in progress: the file `MERGE_HEAD` exists in the git directory. Rebase in progress: `rebase-merge/` or `rebase-apply/` exists there.

## 3. Snapshots

A snapshot is a map from path to `(mode, blob id)`.

| Snapshot | Command |
|---|---|
| Index | `git ls-files -s -z` |
| Commit | `git ls-tree -r -z <sha>` |

- Modes: `100644` regular, `100755` executable, `120000` symlink, `160000` gitlink.
- An index entry with a non-zero stage (unmerged path) is a usage error: `The index has unmerged paths; resolve conflicts first.`
- The listing is loaded once per snapshot and kept in memory, sorted by path.

### 3.1 Reading content

One `git cat-file --batch` process per run, kept open until `GitRepository.close()`.

- Request: the blob id and a newline. Response: `<id> <type> <size>\n`, then `<size>` bytes, then `\n`. A response of `<id> missing` raises `InternalException`.
- Requests are serialized: one outstanding request at a time on the pipe.
- Addressing by blob id, not by path, means no path ever needs quoting, and the id doubles as a content hash for caches.
- Sizes without content come from a second process, `git cat-file --batch-check`, used the same way.
- `readText` returns null when the first 8000 bytes contain a NUL byte, when the bytes are not valid UTF-8, when the size exceeds 5 MiB, or when the entry is a symlink or gitlink. A leading UTF-8 byte order mark is stripped. Line endings are returned as stored.

## 4. Changesets

All diffs use `--name-status -z -M`, so renames are detected and paths are NUL-separated. A rename yields a `FileChange` with `previousPath`; status letters map to `ChangeKind` (`A`, `M`, `D`, `R`, `T`). Copies are not detected.

### 4.1 Pre-commit

```
git diff --cached --name-status -z -M
```

Without an explicit commit, this compares the index with `HEAD`, and with the empty tree on an unborn branch. Base snapshot: `HEAD`, or none.

**Merge in progress.** For each line of `MERGE_HEAD`, and for `HEAD`, list `git diff --cached --name-only -z <parent>`. The changeset is the intersection of those lists; kinds come from the diff against `HEAD`.

### 4.2 Pre-push

Per stdin line `<local ref> <local sha> <remote ref> <remote sha>`:

| Case | Action |
|---|---|
| `<local sha>` is all zeros (branch deletion) | skip |
| `<remote ref>` does not start with `refs/heads/` | skip |
| `<remote sha>` is not all zeros and exists locally | base is `<remote sha>` |
| `<remote sha>` is all zeros, or the object is not present locally | base is `git merge-base <local sha> <sha of every ref under refs/remotes/<remote>/>`; with no refs or no merge base, the empty tree |

Then `git diff --name-status -z -M <base> <local sha>`. Snapshot: the commit `<local sha>`. Target branch: `<remote ref>` without `refs/heads/`.

A line that does not have four space-separated fields is a usage error.

### 4.3 CI

```
git merge-base <base> <head>
git diff --name-status -z -M <merge base> <head>
```

A failing `merge-base` is the usage error of [`cli.md`](cli.md#35-ci---base-ref---head-ref---all---reporter-consolejsongithubjunitsarif). Snapshot: the commit that `<head>` resolves to. Target branch: `<base>` with a leading `origin/` or `refs/heads/` removed.

### 4.4 `--all`

The changeset lists every regular file of the snapshot as `added`. The base snapshot is still resolved, because rules that compare with the base need it.

## 5. Files that differ from the working tree

```
git diff --name-only -z --no-renames            # index snapshot
git diff --name-only -z --no-renames <sha>      # commit snapshot
```

The result is the overlay set of ADR-0001. Untracked files are not part of any snapshot and are invisible to the tool.

## 6. Applying fixes

Index snapshot only. For a list of fixes, in path order:

1. `git diff --name-only -z --no-renames -- <paths>`: remember which of these paths already differ from the working tree.
2. For each fix, `git hash-object -w --stdin --no-filters` with the new content on stdin. `--no-filters` because the content came from the index and is already in repository form.
3. One `git update-index -z --index-info`, fed `<mode> <blob id>\t<path>\0` per fix, with the entry's existing mode.
4. For each path **not** remembered in step 1: `git checkout-index --force -- <path>`, which rewrites the working tree copy through git's filters and line-ending conversion.

The result is one `AppliedFix` per fix with `worktreeUpdated` true or false. A failure in step 3 leaves the index untouched (the command is atomic) and raises `InternalException`; a failure in step 4 is reported as a notice and does not fail the run, since the commit content is already correct.

## 7. Hook script

`application/hooks/hook_script.dart` renders exactly this, with `<hook>` replaced by the hook name, LF line endings and a trailing newline:

```sh
#!/bin/sh
# stagelatch:managed
if command -v stagelatch >/dev/null 2>&1; then
  exec stagelatch run <hook> "$@"
elif command -v stagelatch.bat >/dev/null 2>&1; then
  exec stagelatch.bat run <hook> "$@"
elif command -v dart >/dev/null 2>&1 &&
  dart pub global list 2>/dev/null | grep -q '^stagelatch '; then
  exec dart pub global run stagelatch run <hook> "$@"
fi
echo "stagelatch not found; skipping. Install: dart pub global activate stagelatch" >&2
exit 0
```

A file is **managed** when its second line is exactly `# stagelatch:managed`. If the Windows acceptance test (AC-13) shows a branch does not work in Git for Windows, the template is corrected here first, then in code.

## 8. Hook installer

Hooks directory: the path from section 2, created if absent. For each hook name:

| Existing file | `install` | `install --force` | `uninstall` |
|---|---|---|---|
| none | write script | write script | nothing |
| managed, identical | nothing | nothing | remove; restore backup if any |
| managed, different | overwrite | overwrite | remove; restore backup if any |
| not managed | refuse, exit 64 | back up, then write script | nothing |

- The script file is written with mode `0755` where the platform has modes.
- Backup name: `<hook>.stagelatch-backup`; if that exists, `<hook>.stagelatch-backup.1`, `.2`, and so on. Restore takes the highest number, else the unnumbered one.
- Files ending in `.sample` are ignored.
- When the hooks directory is inside the work tree and tracked (a committed `.githooks/`), `install` adds the notice `The hooks directory is tracked by git; the generated script will show up as a change.`

## 9. Edge cases that must have tests

| Case | Expected behavior |
|---|---|
| `git commit -a`, `git commit <path>` | Git points `GIT_INDEX_FILE` at a temporary index; reads and fixes use it (AC-15) |
| `git commit --amend` | Changeset is index vs `HEAD`; content already in `HEAD` is not re-reported |
| Paths with spaces, quotes, non-ASCII characters, newline | Handled through `-z` and blob ids (AC-11) |
| `core.autocrlf=true` | Index holds LF; fixes are written as LF; `checkout-index` restores CRLF in the working tree (AC-10) |
| CRLF committed as-is | Content is read and compared with CRLF intact; the formatter keeps the file's line ending |
| Submodule (gitlink) entry | Listed, never read; content rules skip it (AC-22) |
| Symlink entry | Listed, never followed; content rules skip it (AC-22) |
| Sparse checkout | The index still lists every path; behavior is unchanged |
| Linked worktree | Layout comes from `rev-parse`; hooks live in the common directory (AC-09) |
| `index.lock` present during a fix | `InternalException` naming the lock; index untouched |
| Detached `HEAD` | No current branch; `pubspec/build-number-regression` does not apply on pre-commit |

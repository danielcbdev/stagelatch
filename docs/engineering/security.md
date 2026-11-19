# Security rules

Status: **Approved (2026-11-12).** Rules are numbered so that reviews and code comments can cite them (`// S3: ...`).

## Threat model

**What we protect**

- The developer's working tree, index and history. Losing uncommitted work is the worst outcome.
- The developer's machine: the tool runs with the user's privileges on every commit.
- CI: the tool runs on pull requests, including ones from forks.

**Who we assume is hostile**

- **Repository content.** File names, file contents and `stagelatch.yaml` in a pull request are attacker-controlled.
- **A compromised dependency** of the tool.

**What we do not defend against**

- A developer who chooses to bypass the hook. CI is the guarantee (ADR-0005).
- Code the project itself asks us to run: `tests/affected` runs the project's tests by design.

## Rules

### S1. Process execution

- Processes are started with an executable and an argument list. A shell is never involved: no `runInShell: true`, no `sh -c`, no string concatenation into a command.
- Only two executables may be started: `git`, and the `dart`/`flutter` binary of the resolved SDK.
- No config key may name a command, script or executable. The single future exception is specified in [`custom-checks.md`](../specs/custom-checks.md) and needs its own approval.
- Arguments that come from repository content are placed after `--` when the command accepts it.

### S2. SDK location

- The resolved SDK's real path (after resolving symlinks) must be **outside** the repository working tree. Otherwise the run ends with a `ConfigException`.
- Reason: `sdk_path` and `.fvm/flutter_sdk` are repository content; a pull request could point them at a committed binary.

### S3. File system writes

The tool writes only to these places, and only after resolving symlinks and confirming the target is inside the stated root:

| Target | Written by | Root |
|---|---|---|
| Index entries | `git update-index` | git |
| Working tree files being refreshed after a fix | `git checkout-index` | git |
| Hook scripts and their backups | `HookInstaller` | hooks directory reported by git |
| `stagelatch.yaml` | `init` | repository root |
| Baseline file | `baseline create`, `baseline prune` | repository root |
| Cache | cache adapter | `<git common dir>/stagelatch/` |

- `RepoPath` rejects absolute paths, `..` segments and NUL. Every path from git or config becomes a `RepoPath` before use.
- The tool never deletes a file it did not create, except restoring a hook backup it made.

### S4. Git mutation allowlist

Mutating git commands the tool may run: `hash-object -w`, `update-index --index-info`, `checkout-index`. Nothing else.

Never: `add`, `stash`, `reset`, `checkout <path>`, `restore`, `clean`, `commit`, `config --add`/`--unset`, `gc`.

- Whether a file has unstaged changes is measured **before** the index is written (ADR-0002).
- All index updates of one run go through a single `update-index --index-info` call so the index is never left half-updated by us.

### S5. Output

- Every string that originates in the repository (paths, YAML values, analyzer messages) is stripped of C0 and C1 control characters before reaching a terminal. Newlines and tabs inside such a string become a single space. An attacker must not be able to move the cursor, recolor output or forge extra lines with a file name.
- The GitHub reporter escapes `%`, `\r`, `\n` in message data and additionally `:` and `,` in properties, per the workflow command rules. Unescaped repository content could inject workflow commands.
- JSON, SARIF and JUnit output is produced by an encoder, never by string concatenation.
- `sensitive-files` findings name the path and the rule. They never print file content, not even a line.
- Environment variable values are never printed, not even with `--verbose`.

### S6. Parsing untrusted input

- Text is read only up to 5 MiB per file; larger files are treated as unreadable by content checks.
- YAML and JSON are parsed with `package:yaml` and `dart:convert`. No custom tags, no code execution.
- Regular expressions applied to repository content must be linear: no nested quantifiers, no backreferences. Each one has a comment stating why it cannot backtrack catastrophically.
- Hand-written scanners (ICU placeholders, ignore comments) are bounded by input length and have tests with adversarial input.

### S7. Network

- The tool opens no sockets. No telemetry, no update check, no remote config.
- `tests/affected` is the only feature that runs project code; what that code does is the project's responsibility.

### S8. CI and release

- Workflows declare `permissions:` explicitly, defaulting to `contents: read`.
- Third-party actions are pinned to a full commit SHA with the version in a comment.
- Workflows that run on pull requests use the `pull_request` event, never `pull_request_target`.
- Publishing to pub.dev uses GitHub OIDC. No token is stored in the repository or its secrets.
- The release workflow runs only on tags created by `release-please` on `main`.

### S9. Dependencies

- See the allowlist in [`coding-standards.md`](coding-standards.md#2-dependencies). `pubspec.lock` is committed.
- Each release pull request includes the output of `dart pub outdated` and a note on any skipped upgrade.

### S10. Temporary files

- Avoided where a pipe works. When needed, created with `Directory.systemTemp.createTemp`, removed in a `finally`, and never given a predictable name.

### S11. Environment

- The environment is inherited unchanged by git so hook variables (`GIT_INDEX_FILE`, `GIT_DIR`) work.
- The tool sets no `GIT_*` variable itself outside tests.

### S12. Hook scripts

- The script is a fixed template. The only substitution is the hook name, taken from a closed enum, never from user input.
- A hook without the `# stagelatch:managed` marker is never overwritten or removed without `--force`, and is always backed up first.

### S13. Config is reviewed code

- A pull request can change `stagelatch.yaml`, add `stagelatch:ignore` comments or extend the baseline, and is then judged by its own rules (ADR-0015). The tool cannot prevent that.
- Mitigation is process: protect these files with code owners, and tell agents not to change them unless asked.

## Security checklist for every pull request

- [ ] No new process execution, or it follows S1.
- [ ] No new write target, or it is added to the S3 table with a containment test.
- [ ] No new git command outside the S4 allowlist.
- [ ] Repository-derived strings pass through the sanitizer before output (S5).
- [ ] New parsers have size bounds and an adversarial-input test (S6).
- [ ] No network access, no new dependency without an ADR (S7, S9).

## Reporting

A `SECURITY.md` at the repository root (created in plan 01) directs reports to GitHub private vulnerability reporting.

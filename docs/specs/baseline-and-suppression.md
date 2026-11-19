# Baseline and suppression specification

Status: **Approved (2026-11-12).** How findings are silenced, from narrowest to broadest: inline ignore, `exclude`, rule level, baseline. Decision records: ADR-0010, ADR-0015.

## 1. Filter chain

The pipeline applies these filters in this order. Each one only removes findings or changes severity; none adds, except step 4.

1. **Selection.** Drop findings whose rule the hook's selectors do not enable.
2. **Levels.** Apply `rules:`: `off` drops, `error`/`warning` override the severity.
3. **Exclude.** Drop findings whose path matches an `exclude` glob.
4. **Inline ignore.** Drop findings covered by a `stagelatch:ignore` comment; add `stagelatch/invalid-ignore` findings. Counted as `suppressed`.
5. **Baseline.** Drop findings matched by the baseline. Counted as `baselined`.

## 2. Inline ignore

Since `0.1.0`.

### 2.1 Syntax

| File kind | Comment |
|---|---|
| `.dart` | `// stagelatch:ignore <ids>` |
| `.yaml`, `.yml` | `# stagelatch:ignore <ids>` |

- `<ids>` is one or more rule IDs separated by commas, with optional spaces around each comma.
- The comment may stand alone on a line or follow code on the same line.
- Anything after the IDs, separated by whitespace, is free text and is ignored: `// stagelatch:ignore tests/new-skip flaky on CI, see #42`.
- The marker is recognized only when `stagelatch:ignore` directly follows the comment opener and optional spaces.
- A comment with no ID suppresses nothing and yields no finding.

### 2.2 Coverage

A comment on line *n* covers findings of the named rules whose start line is *n* or *n + 1*.

### 2.3 Detection

- Lines are scanned in the snapshot text of the finding's file, after the fix phase.
- A line is scanned for the marker with a linear search; no parsing of the host language is attempted. A marker inside a string literal therefore also suppresses. This is accepted: it cannot hide a finding by accident, only by someone writing the marker.
- Files of other kinds (JSON, ARB, binary) have no inline form.

### 2.4 Unknown IDs

An ID that is not a rule of the running version, and is not under `analyze/`, yields `stagelatch/invalid-ignore` at the ID's position, in changed files only.

## 3. `exclude`

- A list of globs in the config ([`config.md`](config.md#4-value-syntax)). A finding whose path matches is dropped.
- `exclude` filters findings; it does not hide files from checks. A check may still read an excluded file to judge another one (a generated part file, for example).
- `format` additionally skips fixing excluded files.

## 4. Baseline

Since `0.2.0`. Purpose: adopt the tool in a repository with existing problems. Baselined findings do not block; new ones do.

### 4.1 File

Path from the `baseline` config key, default `.stagelatch/baseline.json`. UTF-8, two-space indentation, trailing newline, entries sorted by `(path, rule, fingerprint)` so that diffs are minimal.

```json
{
  "version": 1,
  "entries": [
    {
      "rule": "analyze/unused_import",
      "path": "lib/legacy/api.dart",
      "fingerprint": "9f2c5b1e7a3d4c6f8b0a1d2e3f405162738495a6b7c8d9e0f1a2b3c4d5e6f708",
      "count": 2
    }
  ]
}
```

- A missing file is an empty baseline. A file that is not valid JSON, has an unknown `version`, or has a malformed entry is a `ConfigException` (exit 78).
- The file is read from the snapshot (ADR-0015).

### 4.2 Fingerprint

```
fingerprint = SHA-256 hex of UTF-8( rule + "\n" + path + "\n" + normalizedSnippet )
```

- **Snippet:** the lines of the snapshot file from the finding's start line to its end line, inclusive.
- **Normalization:** each line trimmed; runs of spaces and tabs inside a line collapsed to one space; lines joined with one space.
- When the file has no readable text (binary, or the finding is path-based at `1:1` on a non-text file), the snippet is empty.
- Line numbers are not part of the fingerprint, so inserting or removing lines elsewhere in the file does not invalidate entries. Renaming the file does.

### 4.3 Matching

Entries are consumed in the pipeline's sorted finding order. A finding is baselined when an entry with the same rule, path and fingerprint has remaining count; the count then decreases by one. Three identical findings against an entry with `count: 2` leave one finding reported.

Findings of `stagelatch/invalid-ignore` are never baselined.

### 4.4 Baseline commands

**`baseline create [--force]`**

1. Run the pipeline with `--all` on the index, with the selectors of `hooks.ci`, fixes disabled, and an empty baseline.
2. Write every remaining finding (errors and warnings) as entries to the baseline path in the working tree, creating directories.
3. Refuse to overwrite an existing file without `--force` (exit 64): `<path> already exists. Use --force to overwrite, or run: stagelatch baseline prune`.
4. Print `Wrote <n> entr(y|ies) to <path>. Stage it to take effect.` Exit 0.

**`baseline prune`**

1. Run the same pipeline as `create`.
2. For each entry, lower `count` to the number of current findings that match it; remove entries that reach zero. Never add entries or raise counts.
3. Write the file back to the working tree. Print `Removed <n> stale entr(y|ies); <m> remain.` Exit 0. With no baseline file: `No baseline at <path>.`, exit 0.

Both commands leave staging to the developer, consistent with security rule S4.

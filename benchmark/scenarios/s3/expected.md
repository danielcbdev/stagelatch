# Scenario s3

Three files of one feature directory (`lib/features/badges/`) are staged.
A fourth file, imported by two of them, has an unstaged edit.

## `git -C .benchmark/corpus status --short` after `applyScenario`

`staged.patch` goes to the index only, so the working tree of the staged
paths keeps the pinned content and they show as modified on both sides.

```
MM lib/features/badges/biz/bloc/badges_bloc.dart
MM lib/features/badges/domain/badge_catalog.dart
 M lib/features/badges/domain/repositories/badge_repository.dart
MM lib/features/badges/views/widgets/badge_celebrate_sheet.dart
```

## Findings of the snapshot (the three staged files)

Measured with `dart analyze` of the corpus SDK on a tree identical to the
index. The `DIRECTIVES_ORDERING` info exists at the pinned SHA; the other
four are introduced by `staged.patch`.

| Kind | File | Line | Code |
|---|---|---|---|
| error | `badges_bloc.dart` | 24 | `argument_type_not_assignable` |
| warning | `badge_catalog.dart` | 55 | `unused_local_variable` |
| lint | `badge_celebrate_sheet.dart` | 43 | `prefer_const_constructors` |
| info (pre-existing) | `badge_catalog.dart` | 2 | `directives_ordering` |
| unformatted | `badge_celebrate_sheet.dart` | 27 | spacing around `=` and `<` |

The corpus formats with `formatter: page_width: 120`. A formatter that
ignores it reflows lines that are already correct.

## The unstaged trap

`unstaged.patch` renames `BadgeRepository.check()` to `checkAll()` in
`badge_repository.dart`. Analyzed from the working tree, `badges_bloc.dart`
gains:

| Kind | File | Line | Code |
|---|---|---|---|
| error | `badges_bloc.dart` | 23 | `undefined_method` (`check`) |

A probe that honours the overlay never reports it.

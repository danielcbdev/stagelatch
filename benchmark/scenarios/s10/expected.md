# Scenario s10

The three files of s3, plus seven more across the app. One of them,
`lib/core/wallpaper/wallpaper_source.dart`, gains a public getter and is
imported directly by 325 files of the package (`lib/` and `test/`). The
other six gain a doc comment; two of them are `part` files.

## `git -C .benchmark/corpus status --short` after `applyScenario`

```
MM lib/core/wallpaper/wallpaper_source.dart
MM lib/features/badges/biz/bloc/badges_bloc.dart
MM lib/features/badges/domain/badge_catalog.dart
 M lib/features/badges/domain/repositories/badge_repository.dart
MM lib/features/badges/views/widgets/badge_celebrate_sheet.dart
MM lib/features/drops/domain/repositories/drops_repository.dart
MM lib/features/leaderboard/biz/bloc/leaderboard_state.j.dart
MM lib/features/moods/biz/gallery_walls_cubit.dart
MM lib/features/quests/domain/quest_board.dart
MM lib/features/shop/biz/bloc/shop_state.j.dart
MM lib/features/streak/bloc/streak_shop_event.dart
```

## Findings of the snapshot (the ten staged files)

The same four introduced findings as s3, and two pre-existing infos.

| Kind | File | Line | Code |
|---|---|---|---|
| error | `badges_bloc.dart` | 24 | `argument_type_not_assignable` |
| warning | `badge_catalog.dart` | 55 | `unused_local_variable` |
| lint | `badge_celebrate_sheet.dart` | 43 | `prefer_const_constructors` |
| info (pre-existing) | `badge_catalog.dart` | 2 | `directives_ordering` |
| info (pre-existing) | `quest_board.dart` | 4 | `directives_ordering` |
| unformatted | `badge_celebrate_sheet.dart` | 27 | spacing around `=` and `<` |

## The unstaged trap

Identical to s3: `undefined_method` (`check`) at `badges_bloc.dart:23`
when the working tree is analyzed.

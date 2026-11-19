# Fixture scenario s10

The three files of s3, plus `lib/core/hub.dart` (imported by all 110 tiles, gains a getter) and six tiles that gain a doc comment.

The unstaged trap renames `BadgeRepository.check()`, which `badges_bloc.dart` calls.

## `git -C .benchmark/old_sdk status --short` after `applyScenario`

```
MM lib/badges/badge_catalog.dart
 M lib/badges/badge_repository.dart
MM lib/badges/badge_sheet.dart
MM lib/badges/badges_bloc.dart
MM lib/core/hub.dart
MM lib/tiles/tile_003.dart
MM lib/tiles/tile_017.dart
MM lib/tiles/tile_029.dart
MM lib/tiles/tile_048.dart
MM lib/tiles/tile_071.dart
MM lib/tiles/tile_096.dart
```

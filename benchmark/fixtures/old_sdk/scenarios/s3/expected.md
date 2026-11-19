# Fixture scenario s3

Three files of `lib/badges/` staged with one error (`invalid_assignment`), one warning (`unused_local_variable`), one lint (`prefer_const_constructors`) and one unformatted file (`badge_sheet.dart`). `badge_catalog.dart` has a pre-existing `directives_ordering`.

The unstaged trap renames `BadgeRepository.check()`, which `badges_bloc.dart` calls.

## `git -C .benchmark/old_sdk status --short` after `applyScenario`

```
MM lib/badges/badge_catalog.dart
 M lib/badges/badge_repository.dart
MM lib/badges/badge_sheet.dart
MM lib/badges/badges_bloc.dart
```

# Changelog

## [0.1.0](https://github.com/danielcbdev/stagelatch/compare/v0.1.0-dev.1...v0.1.0) (2026-11-20)


### Features

* **checks:** add analyze check on the affected scope ([#44](https://github.com/danielcbdev/stagelatch/issues/44)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **checks:** add format check with index autofix ([#42](https://github.com/danielcbdev/stagelatch/issues/42)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **checks:** add sensitive-files check ([#37](https://github.com/danielcbdev/stagelatch/issues/37)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **cli:** add ci command over the pull request diff ([#41](https://github.com/danielcbdev/stagelatch/issues/41)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **cli:** add doctor command ([#40](https://github.com/danielcbdev/stagelatch/issues/40)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **cli:** add run pre-push over pushed commits ([#38](https://github.com/danielcbdev/stagelatch/issues/38)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **dart:** add directive facts and import graph ([#35](https://github.com/danielcbdev/stagelatch/issues/35)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **dart:** add SDK locator with FVM support and containment rule ([#33](https://github.com/danielcbdev/stagelatch/issues/33)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **dart:** add toolchain adapter over a materialized snapshot ([#39](https://github.com/danielcbdev/stagelatch/issues/39)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **git:** apply fixes through the index without touching unstaged work ([#36](https://github.com/danielcbdev/stagelatch/issues/36)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **packages:** map files to their nearest pubspec ([#34](https://github.com/danielcbdev/stagelatch/issues/34)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **pipeline:** add inline stagelatch:ignore suppression ([#30](https://github.com/danielcbdev/stagelatch/issues/30)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **pipeline:** wire the Dart toolchain over a materialized snapshot ([#45](https://github.com/danielcbdev/stagelatch/issues/45)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **reporters:** add GitHub workflow command reporter ([#32](https://github.com/danielcbdev/stagelatch/issues/32)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))
* **reporters:** add JSON reporter ([#31](https://github.com/danielcbdev/stagelatch/issues/31)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))


### Bug Fixes

* **cli:** accept the arguments git passes to the pre-push hook ([#38](https://github.com/danielcbdev/stagelatch/issues/38)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))


### Performance Improvements

* **dart:** ask the analysis server for the requested files first ([#47](https://github.com/danielcbdev/stagelatch/issues/47)) ([29cf2ee](https://github.com/danielcbdev/stagelatch/commit/29cf2ee69c7d210d8f1edd1487fa65ca8d6e9a2e))

## [0.1.0-dev.1]

### Features

* Add `init`, `install`, `uninstall` and `run pre-commit`.
* Check `pubspec/path-dependency`, `pubspec/dependency-overrides` and
  `pubspec/unparseable` on the staged snapshot.

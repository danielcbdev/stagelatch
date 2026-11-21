# Scenario s10-l10n

The patches of [`s10`](../s10/expected.md), unchanged. The corpus already has an
`l10n.yaml` (`arb-dir: lib/l10n`, `output-dir: lib/l10n/generated`) and a
template with 4,156 keys, so no `l10n.yaml` or template is added: a staged
`.dart` file is enough to make `l10n/unused-key` look at the package, and it
then scans all 2,462 `.dart` files of it.

It exists as its own name so that the published numbers of the gate in
`docs/plans/04-affected.md`, Task 2, say what they measure. Measure with:

```bash
dart run bin/measure_cli.dart --hook pre-commit --scenario s3-l10n --scenario s10-l10n
```

A cold run also deletes the corpus's facts cache.

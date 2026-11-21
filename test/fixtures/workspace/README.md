# Workspace fixture

A pub workspace with two members (`packages/a`, `packages/b`) for AC-28.

No `*_test.dart` files are committed: acceptance tests write them into a
copy at run time. After `dart pub get` at the root, members have no
`.dart_tool/package_config.json` and no `pubspec.lock`; the root holds
both, and `dart test` run in a member's directory resolves through the
root config.

import 'package:stagelatch/src/application/config/default_hooks.dart';
import 'package:test/test.dart';

import '../../support/fake_check_catalog.dart';

void main() {
  List<String> defaults(String hook, FakeCheckCatalog catalog) => [
    for (final selector in defaultHookSelectors(hook, catalog))
      selector.toString(),
  ];

  test('with every check available, the defaults are the documented lists', () {
    final catalog = FakeCheckCatalog.full();

    expect(defaults(preCommitHook, catalog), [
      'format',
      'analyze',
      'codegen',
      'pubspec',
      'l10n',
      'assets',
      'sensitive-files',
      'tests/solo',
      'tests/new-skip',
    ]);
    expect(defaults(prePushHook, catalog), ['analyze', 'tests/affected']);
  });

  test('checks the running version does not have are left out', () {
    final catalog = FakeCheckCatalog(
      rules: {'pubspec/path-dependency', 'pubspec/dependency-overrides'},
    );

    expect(defaults(preCommitHook, catalog), ['pubspec']);
    expect(defaults(prePushHook, catalog), isEmpty);
  });

  test('a rule selector is kept only when that rule exists', () {
    final catalog = FakeCheckCatalog(rules: {'tests/solo'});

    expect(defaults(preCommitHook, catalog), ['tests/solo']);
  });

  test('ci defaults to pre-commit followed by pre-push, without repeats', () {
    final catalog = FakeCheckCatalog.full();

    expect(defaults(ciHook, catalog), [
      'format',
      'analyze',
      'codegen',
      'pubspec',
      'l10n',
      'assets',
      'sensitive-files',
      'tests/solo',
      'tests/new-skip',
      'tests/affected',
    ]);
  });

  test('an unknown hook name is a programming error', () {
    expect(
      () => defaultHookSelectors('post-merge', FakeCheckCatalog.full()),
      throwsArgumentError,
    );
  });
}

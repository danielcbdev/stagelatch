/// What each hook runs when the configuration does not say.
library;

import 'package:stagelatch/src/application/config/check_catalog.dart';
import 'package:stagelatch/src/application/config/hook_selector.dart';

/// The key of the pre-commit list under `hooks`.
const String preCommitHook = 'pre-commit';

/// The key of the pre-push list under `hooks`.
const String prePushHook = 'pre-push';

/// The key of the list `stagelatch ci` uses under `hooks`.
const String ciHook = 'ci';

/// Every key allowed under `hooks`, in the order they are documented.
const List<String> hookNames = [preCommitHook, prePushHook, ciHook];

/// The documented pre-commit default. `tests` is listed rule by rule
/// because `tests/affected` runs the test suite and belongs on push.
const _preCommit = [
  HookSelector('format'),
  HookSelector('analyze'),
  HookSelector('codegen'),
  HookSelector('pubspec'),
  HookSelector('l10n'),
  HookSelector('assets'),
  HookSelector('sensitive-files'),
  HookSelector('tests', 'solo'),
  HookSelector('tests', 'new-skip'),
];

/// The documented pre-push default.
const _prePush = [HookSelector('analyze'), HookSelector('tests', 'affected')];

/// The selectors [hook] runs by default, limited to what [catalog] has.
///
/// The documented lists name checks of the final version. An earlier
/// version drops what it does not implement, so that the default is always
/// valid for the tool that computes it. `ci` defaults to the pre-commit
/// list followed by what the pre-push list adds.
///
/// Throws [ArgumentError] when [hook] is not one of [hookNames].
List<HookSelector> defaultHookSelectors(String hook, CheckCatalog catalog) {
  final documented = switch (hook) {
    preCommitHook => _preCommit,
    prePushHook => _prePush,
    ciHook => unionOfSelectors(_preCommit, _prePush),
    _ => throw ArgumentError.value(hook, 'hook', 'Not a hook name'),
  };
  return [
    for (final selector in documented)
      if (_isAvailable(selector, catalog)) selector,
  ];
}

/// [first] followed by the elements of [second] it does not already have.
List<HookSelector> unionOfSelectors(
  List<HookSelector> first,
  List<HookSelector> second,
) => [
  ...first,
  for (final selector in second)
    if (!first.contains(selector)) selector,
];

bool _isAvailable(HookSelector selector, CheckCatalog catalog) {
  if (!catalog.checkIds.contains(selector.check)) return false;
  final rule = selector.ruleId;
  return rule == null ||
      catalog.hasRule(rule) ||
      catalog.hasDynamicRules(selector.check);
}

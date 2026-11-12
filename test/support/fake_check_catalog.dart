import 'package:stagelatch/src/application/config/check_catalog.dart';
import 'package:stagelatch/src/domain/rule_id.dart';

/// A [CheckCatalog] built from rule ids written as text.
final class FakeCheckCatalog implements CheckCatalog {
  /// Creates a catalog that knows [rules], plus the checks named in
  /// [_dynamicChecks], whose rule names are open-ended.
  new({Set<String> rules = const {}, this._dynamicChecks = const {}})
    : _rules = rules.map(RuleId.parse).toSet();

  /// Every check and rule of the rule catalog, as in the final version.
  factory full() => FakeCheckCatalog(
    rules: const {
      'format/unformatted',
      'sensitive-files/signing',
      'sensitive-files/credentials',
      'pubspec/path-dependency',
      'pubspec/dependency-overrides',
      'pubspec/unparseable',
      'pubspec/unpinned-git',
      'pubspec/build-number-regression',
      'pubspec/lockfile-out-of-sync',
      'codegen/stale',
      'l10n/missing-key',
      'l10n/placeholder-mismatch',
      'l10n/unparseable',
      'l10n/unused-key',
      'assets/missing',
      'assets/undeclared',
      'assets/max-file-size',
      'tests/solo',
      'tests/new-skip',
      'tests/affected',
    },
    dynamicChecks: const {'analyze'},
  );

  final Set<RuleId> _rules;
  final Set<String> _dynamicChecks;

  @override
  Set<String> get checkIds => {
    for (final rule in _rules) rule.check,
    ..._dynamicChecks,
  };

  @override
  bool hasRule(RuleId id) => _rules.contains(id);

  @override
  bool hasDynamicRules(String check) => _dynamicChecks.contains(check);
}

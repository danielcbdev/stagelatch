import 'package:stagelatch/src/checks/l10n/l10n_check.dart';
import 'package:stagelatch/src/checks/l10n/l10n_rules.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_snapshot_files.dart';

const _template = '''
{
  "@@locale": "en",
  "checkoutTitle": "Checkout",
  "greeting": "Hello {name}, you have {count} items",
  "@greeting": {"placeholders": {"name": {}, "count": {}}}
}
''';

/// Portuguese, missing `checkoutTitle`, and a `greeting` without `count`.
const _portuguese = '''
{
  "@@locale": "pt",
  "greeting": "Ola {name}"
}
''';

const _complete = '''
{
  "@@locale": "es",
  "checkoutTitle": "Pago",
  "greeting": "Hola {count} {name}"
}
''';

const _l10n = 'arb-dir: lib/l10n\n';

/// Runs the check over [files]. Every file counts as modified unless
/// [changed] narrows that down; [deleted] paths are not in the snapshot.
Future<List<Finding>> _run(
  Map<String, Object> files, {
  List<String>? changed,
  List<String> deleted = const [],
  List<DartPackage>? packages,
  Set<RuleId>? enabled,
}) async {
  final context = FakeCheckContext(
    snapshot: FakeSnapshotFiles(files),
    changes: ChangeSet([
      for (final path in changed ?? files.keys)
        FileChange(path: RepoPath(path), kind: ChangeKind.modified),
      for (final path in deleted)
        FileChange(path: RepoPath(path), kind: ChangeKind.deleted),
    ]),
    packages: PackageMap(
      packages ?? [const DartPackage(root: null, name: 'app')],
    ),
    // `unused-key` has its own tests; it needs Dart facts, which these
    // translation-only scenarios do not provide.
    enabled:
        enabled ?? {missingKeyRule, placeholderMismatchRule, unparseableRule},
  );
  final result = await const L10nCheck().run(context);
  expect(result.fixes, isEmpty);
  expect(context.dartAccessed, isFalse);
  return result.findings;
}

void main() {
  group('L10nCheck', () {
    test('declares its identity and rules', () {
      const check = L10nCheck();

      expect(check.id, 'l10n');
      expect(check.phase, CheckPhase.verify);
      expect(check.hasDynamicRules, isFalse);
      expect(check.rules.map((rule) => rule.id.toString()), [
        'l10n/missing-key',
        'l10n/placeholder-mismatch',
        'l10n/unparseable',
        'l10n/unused-key',
      ]);
      expect(
        check.rules
            .where((rule) => rule.id != unusedKeyRule)
            .every((rule) => rule.defaultSeverity == Severity.error),
        isTrue,
      );
      expect(
        check.rules
            .singleWhere((rule) => rule.id == unusedKeyRule)
            .defaultSeverity,
        Severity.warning,
      );
      expect(check.rules.every((rule) => rule.summary.endsWith('.')), isTrue);
    });

    test('key missing in a translation, located at the template key', () async {
      final findings = await _run(
        {
          'l10n.yaml': _l10n,
          'lib/l10n/app_en.arb': _template,
          'lib/l10n/app_pt.arb': _portuguese,
        },
        enabled: {missingKeyRule},
      );

      expect(findings, hasLength(1));
      expect(findings.single.rule, missingKeyRule);
      expect(findings.single.severity, Severity.error);
      expect(
        findings.single.message,
        'Key "checkoutTitle" is missing in app_pt.arb.',
      );
      expect(findings.single.location.path, RepoPath('lib/l10n/app_en.arb'));
      expect(findings.single.location.start, const Position(3, 3));
    });

    test('placeholder sets differ', () async {
      final findings = await _run(
        {
          'l10n.yaml': _l10n,
          'lib/l10n/app_en.arb': _template,
          'lib/l10n/app_pt.arb': _portuguese,
        },
        enabled: {placeholderMismatchRule},
      );

      expect(findings, hasLength(1));
      expect(findings.single.rule, placeholderMismatchRule);
      expect(
        findings.single.message,
        'Placeholders of "greeting" differ from the template: expected '
        '{count, name}, found {name}.',
      );
      expect(findings.single.location.path, RepoPath('lib/l10n/app_pt.arb'));
      expect(findings.single.location.start, const Position(3, 3));
    });

    test(
      'a translation with the same placeholders in another order passes',
      () async {
        final findings = await _run({
          'l10n.yaml': _l10n,
          'lib/l10n/app_en.arb': _template,
          'lib/l10n/app_es.arb': _complete,
        });

        expect(findings, isEmpty);
      },
    );

    test('plural arguments are compared by name', () async {
      final findings = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb':
            '{\n  "items": "{n, plural, one{1 item} other{{n} items}}"\n}\n',
        'lib/l10n/app_pt.arb':
            '{\n  "items": "{total, plural, one{1 item} '
            'other{{total} itens}}"\n}\n',
      });

      expect(
        findings.single.message,
        'Placeholders of "items" differ from the template: expected {n}, '
        'found {total}.',
      );
    });

    test('metadata keys (@key, @@locale) are not messages', () async {
      final findings = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb': _template,
        // No `@greeting` and no `@@locale` here: metadata is never required.
        'lib/l10n/app_es.arb':
            '{\n  "checkoutTitle": "Pago",\n  "greeting": "Hola {name} '
            '{count}"\n}\n',
      });

      expect(findings, isEmpty);
    });

    test(
      'a non-string message value is ignored by the placeholder rule',
      () async {
        final findings = await _run({
          'l10n.yaml': _l10n,
          'lib/l10n/app_en.arb': '{\n  "a": "Hi {name}",\n  "b": 3\n}\n',
          'lib/l10n/app_pt.arb': '{\n  "a": {"x": 1},\n  "b": "Oi {name}"\n}\n',
        });

        expect(findings, isEmpty);
      },
    );

    test('extra keys in a translation are not reported', () async {
      final findings = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb': '{\n  "a": "A"\n}\n',
        'lib/l10n/app_pt.arb': '{\n  "a": "A",\n  "extra": "E"\n}\n',
      });

      expect(findings, isEmpty);
    });

    test('invalid JSON yields l10n/unparseable and the file is skipped by the '
        'other rules', () async {
      final findings = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb': _template,
        'lib/l10n/app_pt.arb': '{\n  "greeting": "Ola {name}",\n',
      });

      expect(findings, hasLength(1));
      expect(findings.single.rule, unparseableRule);
      expect(findings.single.severity, Severity.error);
      expect(
        findings.single.message,
        startsWith('app_pt.arb is not valid JSON: '),
      );
      expect(findings.single.message, endsWith('.'));
      expect(findings.single.location.path, RepoPath('lib/l10n/app_pt.arb'));
    });

    test('a root that is not an object is unparseable', () async {
      final findings = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb': _template,
        'lib/l10n/app_pt.arb': '["a", "b"]\n',
      });

      expect(
        findings.single.message,
        'app_pt.arb is not valid JSON: expected an object at the top level.',
      );
      expect(
        findings.single.location,
        Location.wholeFile(RepoPath('lib/l10n/app_pt.arb')),
      );
    });

    test('an unparseable template skips every comparison', () async {
      final findings = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb': '{ "a": ',
        'lib/l10n/app_pt.arb': _portuguese,
      });

      expect(findings.map((f) => f.rule), [unparseableRule]);
      expect(findings.single.location.path, RepoPath('lib/l10n/app_en.arb'));
    });

    test(
      'an unparseable translation that did not change is not reported',
      () async {
        final findings = await _run(
          {
            'l10n.yaml': _l10n,
            'lib/l10n/app_en.arb': _template,
            'lib/l10n/app_pt.arb': '{ broken',
            'lib/l10n/app_es.arb': _complete,
          },
          changed: ['lib/l10n/app_en.arb'],
        );

        expect(findings, isEmpty);
      },
    );

    test('the check runs when any ARB of the directory or l10n.yaml changed, '
        'and compares all locales', () async {
      final files = {
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb': _template,
        'lib/l10n/app_pt.arb': _portuguese,
        'lib/l10n/app_es.arb': _complete,
      };

      for (final changed in [
        'lib/l10n/app_es.arb',
        'lib/l10n/app_en.arb',
        'l10n.yaml',
      ]) {
        final findings = await _run(files, changed: [changed]);
        expect(findings.map((f) => f.rule).toSet(), {
          missingKeyRule,
          placeholderMismatchRule,
        }, reason: 'a change to $changed compares the pt locale too');
      }
    });

    test('an unrelated change does not run the check', () async {
      final findings = await _run(
        {
          'l10n.yaml': _l10n,
          'lib/l10n/app_en.arb': _template,
          'lib/l10n/app_pt.arb': _portuguese,
          'lib/main.dart': '',
        },
        changed: ['lib/main.dart'],
      );

      expect(findings, isEmpty);
    });

    test('a deleted ARB file triggers the comparison of the rest', () async {
      final findings = await _run(
        {
          'l10n.yaml': _l10n,
          'lib/l10n/app_en.arb': _template,
          'lib/l10n/app_pt.arb': _portuguese,
        },
        changed: const [],
        deleted: ['lib/l10n/app_es.arb'],
      );

      expect(findings.map((f) => f.rule).toSet(), {
        missingKeyRule,
        placeholderMismatchRule,
      });
    });

    test('only ARB files directly in the directory count', () async {
      final findings = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb': _template,
        'lib/l10n/old/app_pt.arb': _portuguese,
        'lib/l10n/notes.txt': 'x',
      });

      expect(findings, isEmpty);
    });

    test('a package without l10n.yaml is skipped', () async {
      final findings = await _run({
        'lib/l10n/app_en.arb': _template,
        'lib/l10n/app_pt.arb': _portuguese,
      });

      expect(findings, isEmpty);
    });

    test('a missing template says nothing', () async {
      final findings = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_pt.arb': _portuguese,
      });

      expect(findings, isEmpty);
    });

    test('arb-dir and template-arb-file come from l10n.yaml', () async {
      final findings = await _run(
        {
          'l10n.yaml': 'arb-dir: res\ntemplate-arb-file: intl_en.arb\n',
          'res/intl_en.arb': _template,
          'res/intl_pt.arb': _portuguese,
        },
        enabled: {missingKeyRule},
      );

      expect(
        findings.single.message,
        'Key "checkoutTitle" is missing in intl_pt.arb.',
      );
      expect(findings.single.location.path, RepoPath('res/intl_en.arb'));
    });

    test('each package with an l10n.yaml is checked on its own', () async {
      final findings = await _run(
        {
          'packages/ui/l10n.yaml': _l10n,
          'packages/ui/lib/l10n/app_en.arb': _template,
          'packages/ui/lib/l10n/app_pt.arb': _portuguese,
          'packages/core/l10n.yaml': _l10n,
          'packages/core/lib/l10n/app_en.arb': '{\n  "a": "A"\n}\n',
          'packages/core/lib/l10n/app_pt.arb': '{\n  "a": "A"\n}\n',
        },
        packages: [
          DartPackage(root: RepoPath('packages/ui'), name: 'ui'),
          DartPackage(root: RepoPath('packages/core'), name: 'core'),
        ],
      );

      expect(findings.map((f) => f.location.path.value).toSet(), {
        'packages/ui/lib/l10n/app_en.arb',
        'packages/ui/lib/l10n/app_pt.arb',
      });
    });

    test('a disabled rule produces nothing', () async {
      final files = {
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb': _template,
        'lib/l10n/app_pt.arb': _portuguese,
        'lib/l10n/app_xx.arb': '{ nope',
      };

      Future<List<RuleId>> only(RuleId rule) async => [
        for (final finding in await _run(files, enabled: {rule})) finding.rule,
      ];

      expect(await only(missingKeyRule), [missingKeyRule]);
      expect(await only(placeholderMismatchRule), [placeholderMismatchRule]);
      expect(await only(unparseableRule), [unparseableRule]);
    });
  });
}

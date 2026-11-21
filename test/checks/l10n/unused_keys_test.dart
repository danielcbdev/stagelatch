import 'package:stagelatch/src/checks/codegen/codegen_settings.dart';
import 'package:stagelatch/src/checks/l10n/l10n_check.dart';
import 'package:stagelatch/src/checks/l10n/l10n_rules.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_dart_toolchain.dart';
import '../../support/fake_snapshot_files.dart';

const _template = '''
{
  "@@locale": "en",
  "checkoutTitle": "Checkout",
  "@checkoutTitle": {"description": "never a key"},
  "legacyBanner": "Old"
}
''';

const _l10n = 'arb-dir: lib/l10n\n';

/// A Dart file that uses `checkoutTitle` and nothing else.
const _usesCheckout = '''
import 'package:flutter/widgets.dart';

Widget build(AppLocalizations l10n) => Text(l10n.checkoutTitle);
''';

/// Uses `legacyBanner` through a member access and `checkoutTitle` through
/// a bare interpolation.
const _usesBoth = r'''
String f(AppLocalizations l10n) =>
    '${l10n.legacyBanner} $checkoutTitle';
''';

const _app = DartPackage(root: null, name: 'app');

DartPackage _package(String root) =>
    DartPackage(root: RepoPath(root), name: root.split('/').last);

/// Runs the whole check. Every ARB file counts as changed unless [changed]
/// narrows that down; [extra] adds changes (deletes, renames).
Future<({List<Finding> findings, FakeDartToolchain dart})> _run(
  Map<String, Object> files, {
  List<String>? changed,
  List<FileChange> extra = const [],
  List<DartPackage> packages = const [_app],
  Set<RuleId>? enabled,
  CodegenSettings codegen = const CodegenSettings(),
}) async {
  final dart = FakeDartToolchain();
  final context = FakeCheckContext(
    snapshot: FakeSnapshotFiles(files),
    changes: ChangeSet([
      for (final path
          in changed ?? files.keys.where((path) => path.endsWith('.arb')))
        FileChange(path: RepoPath(path), kind: ChangeKind.modified),
      ...extra,
    ]),
    packages: PackageMap(packages),
    dart: dart,
    enabled: enabled,
    settings: [codegen],
  );
  final result = await const L10nCheck().run(context);
  return (
    findings: [
      for (final finding in result.findings)
        if (finding.rule == unusedKeyRule) finding,
    ],
    dart: dart,
  );
}

Map<String, Object> _project(Map<String, Object> dart) => {
  'l10n.yaml': _l10n,
  'lib/l10n/app_en.arb': _template,
  ...dart,
};

void main() {
  group('l10n/unused-key', () {
    test('a key referenced nowhere is reported at the template key', () async {
      final result = await _run(
        _project({'lib/main.dart': _usesCheckout}),
        changed: ['lib/l10n/app_en.arb'],
      );

      final f = result.findings;
      expect(f, hasLength(1));
      expect(
        f.single.message,
        'Key "legacyBanner" is not referenced by any Dart file.',
      );
      expect(f.single.severity, Severity.warning);
      expect(f.single.location.path, RepoPath('lib/l10n/app_en.arb'));
      expect(f.single.location.start, const Position(5, 3));
    });

    test('a key used through l10n.key, a getter chain or an interpolation '
        'is used', () async {
      final chain = await _run(
        _project({
          'lib/a.dart': 'var x = AppLocalizations.of(context).checkoutTitle;',
          'lib/b.dart': r"var y = '${l10n.legacyBanner}';",
        }),
      );
      final interpolated = await _run(_project({'lib/c.dart': _usesBoth}));

      expect(chain.findings, isEmpty);
      expect(interpolated.findings, isEmpty);
    });

    test('a reference in a comment or a string does not count', () async {
      final result = await _run(
        _project({
          'lib/a.dart':
              '// checkoutTitle legacyBanner\n'
              "var s = 'checkoutTitle legacyBanner';",
        }),
      );

      expect(result.findings.map((f) => f.message), [
        'Key "checkoutTitle" is not referenced by any Dart file.',
        'Key "legacyBanner" is not referenced by any Dart file.',
      ]);
    });

    test('a reference in a generated file does not count', () async {
      final result = await _run({
        'l10n.yaml': 'arb-dir: lib/l10n\noutput-dir: lib/gen\n',
        'lib/l10n/app_en.arb': _template,
        'lib/gen/app_localizations.dart':
            'String get checkoutTitle => "";\nString get legacyBanner => "";',
        'lib/model.g.dart': 'var a = checkoutTitle; var b = legacyBanner;',
        'lib/model.freezed.dart': 'var a = checkoutTitle;',
        'lib/real.dart': '',
      });

      expect(result.findings, hasLength(2));
    });

    test('when output-dir is omitted, arb-dir is excluded from the '
        'scan', () async {
      final result = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb': _template,
        'lib/l10n/app_localizations.dart':
            'String get checkoutTitle => "";\nString get legacyBanner => "";',
        'lib/l10n/app_localizations_en.dart': 'String get checkoutTitle => "";',
        'lib/real.dart': '',
      });

      expect(result.findings, hasLength(2));
      expect(result.dart.factsCalls, [RepoPath('lib/real.dart')]);
    });

    test('a reference in another package does not count', () async {
      final result = await _run(
        _project({
          'lib/a.dart': _usesCheckout,
          'packages/b/lib/x.dart': _usesBoth,
        }),
        packages: [_app, _package('packages/b')],
      );

      expect(result.findings.map((f) => f.message), [
        'Key "legacyBanner" is not referenced by any Dart file.',
      ]);
    });

    test('the rule scans the whole package, not the changeset', () async {
      final result = await _run(
        _project({'lib/unchanged.dart': _usesBoth, 'lib/other.dart': ''}),
        changed: ['lib/l10n/app_en.arb'],
      );

      expect(result.findings, isEmpty);
      expect(result.dart.factsCalls, contains(RepoPath('lib/unchanged.dart')));
    });

    test('the rule looks at the package when a Dart file of it changed even '
        'if no ARB did', () async {
      final result = await _run(
        _project({'lib/a.dart': _usesCheckout}),
        changed: ['lib/a.dart'],
      );

      expect(result.findings.map((f) => f.message), [
        'Key "legacyBanner" is not referenced by any Dart file.',
      ]);
    });

    test('a package looked at only because of a Dart change runs no other '
        'rule', () async {
      final result = await _run(
        _project({
          'lib/a.dart': _usesBoth,
          // A translation that lacks every key of the template.
          'lib/l10n/app_pt.arb': '{"other": "x"}',
        }),
        changed: ['lib/a.dart'],
      );

      // _run keeps only unused-key; go through the check for the rest.
      final context = FakeCheckContext(
        snapshot: FakeSnapshotFiles(
          _project({
            'lib/a.dart': _usesBoth,
            'lib/l10n/app_pt.arb': '{"other": "x"}',
          }),
        ),
        changes: ChangeSet([
          FileChange(path: RepoPath('lib/a.dart'), kind: ChangeKind.modified),
        ]),
        packages: PackageMap(const [_app]),
        dart: FakeDartToolchain(),
        settings: const [CodegenSettings()],
      );
      final all = await const L10nCheck().run(context);

      expect(result.findings, isEmpty);
      expect(all.findings, isEmpty);
    });

    test('a deleted Dart file triggers it', () async {
      final result = await _run(
        _project({'lib/a.dart': _usesCheckout}),
        changed: const [],
        extra: [
          FileChange(path: RepoPath('lib/gone.dart'), kind: ChangeKind.deleted),
        ],
      );

      expect(result.findings, hasLength(1));
    });

    test('a renamed Dart file triggers it under either path', () async {
      final files = _project({'lib/a.dart': _usesCheckout});
      final packages = [_app, _package('packages/b')];

      final newPath = await _run(
        files,
        changed: const [],
        packages: packages,
        extra: [
          FileChange(
            path: RepoPath('lib/a.dart'),
            kind: ChangeKind.renamed,
            previousPath: RepoPath('packages/b/lib/a.dart'),
          ),
        ],
      );
      final oldPath = await _run(
        files,
        changed: const [],
        packages: packages,
        extra: [
          FileChange(
            path: RepoPath('packages/b/lib/a.dart'),
            kind: ChangeKind.renamed,
            previousPath: RepoPath('lib/a.dart'),
          ),
        ],
      );
      // Moved out of the package: the old path alone is in it.
      final movedOut = await _run(
        files,
        changed: const [],
        packages: packages,
        extra: [
          FileChange(
            path: RepoPath('packages/b/lib/a.dart'),
            kind: ChangeKind.renamed,
            previousPath: RepoPath('lib/old.dart'),
          ),
        ],
      );

      expect(newPath.findings, hasLength(1));
      expect(oldPath.findings, hasLength(1));
      expect(movedOut.findings, hasLength(1));
    });

    test('a Dart file of another package does not trigger it', () async {
      final result = await _run(
        {
          ..._project({'lib/a.dart': _usesCheckout}),
          'packages/b/lib/x.dart': '',
        },
        changed: ['packages/b/lib/x.dart'],
        packages: [_app, _package('packages/b')],
      );

      expect(result.findings, isEmpty);
      expect(result.dart.factsCalls, isEmpty);
    });

    test('a non-Dart file does not trigger it', () async {
      final result = await _run(
        _project({'lib/a.dart': _usesCheckout, 'README.md': ''}),
        changed: ['README.md'],
      );

      expect(result.findings, isEmpty);
      expect(result.dart.factsCalls, isEmpty);
    });

    test('a package with a file that is not well formed produces no '
        'finding', () async {
      final result = await _run(
        _project({
          'lib/a.dart': _usesCheckout,
          'lib/broken.dart': "var s = 'unterminated;",
        }),
      );

      expect(result.findings, isEmpty);
    });

    test('a package with a file whose facts cannot be read produces no '
        'finding', () async {
      final result = await _run(
        _project({
          'lib/a.dart': _usesCheckout,
          'lib/unreadable.dart': [0x00],
        }),
      );

      expect(result.findings, isEmpty);
      expect(result.dart.factsCalls, contains(RepoPath('lib/unreadable.dart')));
    });

    test('a template that is missing or not an object produces no '
        'finding', () async {
      final missing = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_pt.arb': '{"x": "y"}',
        'lib/a.dart': '',
      });
      final notObject = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb': '[1]',
        'lib/a.dart': '',
      });
      final invalid = await _run({
        'l10n.yaml': _l10n,
        'lib/l10n/app_en.arb': '{',
        'lib/a.dart': '',
      });

      expect(missing.findings, isEmpty);
      expect(notObject.findings, isEmpty);
      expect(invalid.findings, isEmpty);
    });

    test('metadata keys starting with @ are not keys', () async {
      final result = await _run(
        _project({
          'lib/a.dart': 'var a = legacyBanner; var b = checkoutTitle;',
        }),
      );

      // "@checkoutTitle" and "@@locale" would be reported if they were keys.
      expect(result.findings, isEmpty);
    });

    test('a package without l10n.yaml is not looked at', () async {
      final result = await _run(
        {'lib/a.dart': '', 'lib/l10n/app_en.arb': _template},
        changed: ['lib/a.dart'],
      );

      expect(result.findings, isEmpty);
      expect(result.dart.factsCalls, isEmpty);
    });

    test('a nested package is judged by its own files', () async {
      final result = await _run(
        {
          'l10n.yaml': _l10n,
          'lib/l10n/app_en.arb': _template,
          'lib/a.dart': _usesCheckout,
          'packages/b/l10n.yaml': _l10n,
          'packages/b/lib/l10n/app_en.arb': '{"onlyB": "x"}',
          'packages/b/lib/b.dart': _usesBoth,
        },
        packages: [_app, _package('packages/b')],
        changed: ['lib/l10n/app_en.arb', 'packages/b/lib/l10n/app_en.arb'],
      );

      expect(result.findings.map((f) => '${f.location.path} ${f.message}'), [
        'lib/l10n/app_en.arb Key "legacyBanner" is not referenced by any Dart file.',
        'packages/b/lib/l10n/app_en.arb Key "onlyB" is not referenced by any Dart file.',
      ]);
    });

    test('generated_suffixes of the configuration are honoured', () async {
      final result = await _run(
        _project({
          'lib/a.dart': _usesCheckout,
          'lib/x.gen.dart': 'var a = legacyBanner;',
        }),
        codegen: const CodegenSettings(generatedSuffixes: ['.gen.dart']),
      );

      expect(result.findings, hasLength(1));
    });

    test('the rule is declared as a warning by default', () {
      expect(unusedKeyRule.toString(), 'l10n/unused-key');
      final descriptor = l10nRuleDescriptors.singleWhere(
        (rule) => rule.id == unusedKeyRule,
      );
      expect(descriptor.defaultSeverity, Severity.warning);
      expect(
        descriptor.summary,
        'A key of the template is not used by any Dart file.',
      );
    });

    test('the rule runs alone when it is the only one enabled', () async {
      final result = await _run(
        _project({'lib/a.dart': _usesCheckout}),
        enabled: {unusedKeyRule},
      );

      expect(result.findings, hasLength(1));
    });

    test('the rule can be off: no facts are requested', () async {
      final result = await _run(
        _project({'lib/a.dart': _usesCheckout}),
        changed: ['lib/a.dart', 'lib/l10n/app_en.arb'],
        enabled: {missingKeyRule, placeholderMismatchRule, unparseableRule},
      );

      expect(result.findings, isEmpty);
      expect(result.dart.factsCalls, isEmpty);
    });
  });
}

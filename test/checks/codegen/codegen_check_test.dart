import 'package:stagelatch/src/checks/codegen/codegen_check.dart';
import 'package:stagelatch/src/checks/codegen/codegen_rules.dart';
import 'package:stagelatch/src/checks/codegen/codegen_settings.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_check_context.dart';
import '../../support/fake_dart_toolchain.dart';
import '../../support/fake_snapshot_files.dart';

/// An annotated class with a generated part, with [body] as its body.
String _order({String body = 'final int id;', String extra = ''}) =>
    '''
import 'package:json_annotation/json_annotation.dart';

part 'order.g.dart';

@JsonSerializable()
class Order {
  $body
}
$extra''';

const _generated = "// GENERATED CODE\npart of 'order.dart';\n";

/// Runs the check. Every path of [files] is changed unless [changed] says
/// otherwise; [renamed] maps a new path to its path in [base].
Future<List<Finding>> _run(
  Map<String, Object> files, {
  Map<String, Object>? base,
  List<String>? changed,
  Map<String, String> renamed = const {},
  List<String> deleted = const [],
  CodegenSettings settings = const CodegenSettings(),
  Set<RuleId>? enabled,
}) async {
  final context = FakeCheckContext(
    snapshot: FakeSnapshotFiles(files),
    base: base == null ? null : FakeSnapshotFiles(base),
    changes: ChangeSet([
      for (final path in changed ?? files.keys)
        if (renamed.containsKey(path))
          FileChange(
            path: RepoPath(path),
            kind: ChangeKind.renamed,
            previousPath: RepoPath(renamed[path]!),
          )
        else
          FileChange(
            path: RepoPath(path),
            kind: base == null || base.containsKey(path)
                ? ChangeKind.modified
                : ChangeKind.added,
          ),
      for (final path in deleted)
        FileChange(path: RepoPath(path), kind: ChangeKind.deleted),
    ]),
    dart: FakeDartToolchain(),
    enabled: enabled,
    settings: [settings],
  );
  final result = await const CodegenCheck().run(context);
  expect(result.fixes, isEmpty);
  return result.findings;
}

void main() {
  group('CodegenCheck', () {
    test('declares its identity and rule', () {
      const check = CodegenCheck();

      expect(check.id, 'codegen');
      expect(check.phase, CheckPhase.verify);
      expect(check.hasDynamicRules, isFalse);
      expect(check.rules.map((rule) => rule.id.toString()), ['codegen/stale']);
      expect(check.rules.single.defaultSeverity, Severity.error);
      expect(check.rules.single.summary.endsWith('.'), isTrue);
    });

    test(
      'annotated class changed, generated part not in the changeset',
      () async {
        final findings = await _run(
          {
            'lib/order.dart': _order(body: 'final int id;\n  final int qty;'),
            'lib/order.g.dart': _generated,
          },
          base: {'lib/order.dart': _order(), 'lib/order.g.dart': _generated},
          changed: ['lib/order.dart'],
        );

        expect(findings, hasLength(1));
        expect(findings.single.rule, staleRule);
        expect(findings.single.severity, Severity.error);
        expect(
          findings.single.message,
          '"Order" changed but order.g.dart was not updated in this change.',
        );
        expect(findings.single.location.path, RepoPath('lib/order.dart'));
        // The annotations of `Order`.
        expect(findings.single.location.start, const Position(5, 1));
      },
    );

    test(
      'same change with the generated part in the changeset passes',
      () async {
        final findings = await _run(
          {
            'lib/order.dart': _order(body: 'final int id;\n  final int qty;'),
            'lib/order.g.dart': _generated,
          },
          base: {'lib/order.dart': _order(), 'lib/order.g.dart': _generated},
        );

        expect(findings, isEmpty);
      },
    );

    test('only non-annotated code changed: no finding', () async {
      final findings = await _run(
        {
          'lib/order.dart': _order(extra: 'class Helper { int x = 1; }'),
          'lib/order.g.dart': _generated,
        },
        base: {
          'lib/order.dart': _order(extra: 'class Helper { int x = 0; }'),
          'lib/order.g.dart': _generated,
        },
        changed: ['lib/order.dart'],
      );

      expect(findings, isEmpty);
    });

    test('formatting and comments alone do not trigger it', () async {
      final findings = await _run(
        {
          'lib/order.dart': _order(body: '// note\n  final   int   id ;'),
          'lib/order.g.dart': _generated,
        },
        base: {'lib/order.dart': _order(), 'lib/order.g.dart': _generated},
        changed: ['lib/order.dart'],
      );

      expect(findings, isEmpty);
    });

    test('new source file whose generated part is absent', () async {
      final findings = await _run(
        {'lib/order.dart': _order()},
        base: {'lib/other.dart': ''},
      );

      expect(findings, hasLength(1));
      expect(
        findings.single.message,
        'order.g.dart is declared as a part but is missing.',
      );
      expect(findings.single.location.path, RepoPath('lib/order.dart'));
      // The URI literal of the `part` directive.
      expect(findings.single.location.start, const Position(3, 6));
    });

    test('a missing part is reported even when nothing annotated '
        'changed', () async {
      final findings = await _run(
        {'lib/order.dart': _order(extra: 'class H {}')},
        base: {'lib/order.dart': _order()},
        changed: ['lib/order.dart'],
      );

      expect(
        findings.single.message,
        'order.g.dart is declared as a part but is missing.',
      );
    });

    test(
      'a new source file with its part present but not changed is stale',
      () async {
        final findings = await _run(
          {'lib/order.dart': _order(), 'lib/order.g.dart': _generated},
          base: {'lib/order.g.dart': _generated},
          changed: ['lib/order.dart'],
        );

        expect(
          findings.single.message,
          '"Order" changed but order.g.dart was not updated in this change.',
        );
        // New file: the `part` directive, not the declaration.
        expect(findings.single.location.start, const Position(3, 6));
      },
    );

    test(
      'renamed source file is compared with its previous path in the base',
      () async {
        final unchanged = await _run(
          {'lib/order.dart': _order(), 'lib/order.g.dart': _generated},
          base: {
            'lib/old_order.dart': _order(),
            'lib/order.g.dart': _generated,
          },
          changed: ['lib/order.dart'],
          renamed: {'lib/order.dart': 'lib/old_order.dart'},
        );
        final edited = await _run(
          {
            'lib/order.dart': _order(body: 'final int id;\n  final int qty;'),
            'lib/order.g.dart': _generated,
          },
          base: {
            'lib/old_order.dart': _order(),
            'lib/order.g.dart': _generated,
          },
          changed: ['lib/order.dart'],
          renamed: {'lib/order.dart': 'lib/old_order.dart'},
        );

        expect(unchanged, isEmpty);
        expect(edited.single.message, startsWith('"Order" changed'));
      },
    );

    test('a part in a subdirectory is resolved against the source and named '
        'as written', () async {
      final source = _order().replaceAll(
        "part 'order.g.dart'",
        "part 'gen/order.g.dart'",
      );
      final findings = await _run(
        {
          'lib/order.dart': source.replaceAll(
            'final int id;',
            'final int id2;',
          ),
          'lib/gen/order.g.dart': _generated,
        },
        base: {'lib/order.dart': source, 'lib/gen/order.g.dart': _generated},
        changed: ['lib/order.dart'],
      );

      expect(
        findings.single.message,
        '"Order" changed but gen/order.g.dart was not updated in this change.',
      );
    });

    test('two generated parts: only the one missing from the changeset is '
        'reported', () async {
      final source = _order().replaceAll(
        "part 'order.g.dart';",
        "part 'order.g.dart';\npart 'order.freezed.dart';",
      );
      final edited = source.replaceAll('final int id;', 'final int id2;');
      final findings = await _run(
        {
          'lib/order.dart': edited,
          'lib/order.g.dart': _generated,
          'lib/order.freezed.dart': _generated,
        },
        base: {
          'lib/order.dart': source,
          'lib/order.g.dart': _generated,
          'lib/order.freezed.dart': _generated,
        },
        changed: ['lib/order.dart', 'lib/order.g.dart'],
      );

      expect(
        findings.single.message,
        '"Order" changed but order.freezed.dart was not updated in this '
        'change.',
      );
    });

    test(
      'a removed annotated declaration is reported at the part directive',
      () async {
        final findings = await _run(
          {
            'lib/order.dart': _order().replaceAll('@JsonSerializable()\n', ''),
            'lib/order.g.dart': _generated,
          },
          base: {'lib/order.dart': _order(), 'lib/order.g.dart': _generated},
          changed: ['lib/order.dart'],
        );

        expect(
          findings.single.message,
          '"Order" changed but order.g.dart was not updated in this change.',
        );
        expect(findings.single.location.start, const Position(3, 6));
      },
    );

    test('only the list of parts changing names the file', () async {
      final base = _order();
      final withPart = base.replaceAll(
        "part 'order.g.dart';",
        "part 'order.g.dart';\npart 'order.freezed.dart';",
      );
      final findings = await _run(
        {
          'lib/order.dart': withPart,
          'lib/order.g.dart': _generated,
          'lib/order.freezed.dart': _generated,
        },
        base: {'lib/order.dart': base, 'lib/order.g.dart': _generated},
        changed: ['lib/order.dart', 'lib/order.g.dart'],
      );

      expect(
        findings.single.message,
        '"order.dart" changed but order.freezed.dart was not updated in this '
        'change.',
      );
    });

    test(
      'a part that is not a configured suffix does not make a source file',
      () async {
        final findings = await _run({
          'lib/order.dart': "part 'helpers.dart';\n@a class A {}\n",
        });

        expect(findings, isEmpty);
      },
    );

    test('custom generated_suffixes are honored', () async {
      final findings = await _run({
        'lib/order.dart': "part 'order.config.dart';\n@injectable class A {}\n",
      }, settings: const CodegenSettings(generatedSuffixes: ['.config.dart']));

      expect(
        findings.single.message,
        'order.config.dart is declared as a part but is missing.',
      );
    });

    test('generated_files_committed: false disables the check', () async {
      final findings = await _run({
        'lib/order.dart': _order(),
      }, settings: const CodegenSettings(generatedFilesCommitted: false));

      expect(findings, isEmpty);
    });

    test('a file the lexer cannot read is left to analyze', () async {
      final findings = await _run({
        'lib/order.dart':
            "part 'order.g.dart';\n@a class A { final x = 'oops;\n",
      });

      expect(findings, isEmpty);
    });

    test('no base (first commit) treats the file as new', () async {
      final findings = await _run(
        {'lib/order.dart': _order(), 'lib/order.g.dart': _generated},
        changed: ['lib/order.dart'],
      );

      expect(
        findings.single.message,
        '"Order" changed but order.g.dart was not updated in this change.',
      );
    });

    test('files that are not changed Dart sources are ignored', () async {
      final findings = await _run(
        {'lib/order.dart': _order(), 'README.md': 'x'},
        changed: ['README.md'],
        deleted: ['lib/old.dart'],
      );

      expect(findings, isEmpty);
    });

    test('every source file is judged on its own', () async {
      final findings = await _run({
        'lib/a.dart': "part 'a.g.dart';\n@a class A {}\n",
        'lib/b.dart': "part 'b.g.dart';\n@b class B {}\n",
        'lib/b.g.dart': _generated,
      });

      expect(findings.map((f) => f.location.path.value), ['lib/a.dart']);
    });

    test('a disabled rule produces nothing', () async {
      final findings = await _run(
        {'lib/order.dart': _order()},
        enabled: {const RuleId('pubspec', 'unparseable')},
      );

      expect(findings, isEmpty);
    });
  });
}

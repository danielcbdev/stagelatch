import 'package:stagelatch/src/checks/codegen/codegen_signature.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';
import 'package:test/test.dart';

const _suffixes = ['.g.dart', '.freezed.dart'];

CodegenSignature _signature(
  String source, {
  List<String> suffixes = _suffixes,
}) => CodegenSignature.of(
  const SyntacticFacts().extract(source, RepoPath('lib/a.dart')),
  suffixes,
);

const _base = '''
part 'a.g.dart';

@JsonSerializable()
class A {
  final int x;
}

@freezed
class B {
  final int y;
}
''';

void main() {
  group('of', () {
    test('generated parts are the part URIs with a configured suffix, in '
        'order', () {
      final signature = _signature('''
part 'a.g.dart';
part 'helpers.dart';
part 'gen/a.freezed.dart';
part of 'lib.dart';
''');

      expect(signature.generatedParts, ['a.g.dart', 'gen/a.freezed.dart']);
    });

    test('custom suffixes replace the defaults', () {
      final signature = _signature(
        "part 'a.g.dart';\npart 'a.config.dart';\n",
        suffixes: ['.config.dart'],
      );

      expect(signature.generatedParts, ['a.config.dart']);
    });

    test('a file without generated parts has none', () {
      expect(
        _signature("import 'a.dart';\nclass A {}").generatedParts,
        isEmpty,
      );
    });

    test('partDirectives locate the generated parts', () {
      final signature = _signature("part 'a.g.dart';\n");

      expect(signature.partDirectives.single.uri, 'a.g.dart');
      expect(
        signature.partDirectives.single.location.start,
        const Position(1, 6),
      );
    });
  });

  group('firstDifference', () {
    test('equal signatures have none', () {
      expect(_signature(_base).firstDifference(_signature(_base)), isNull);
    });

    test('formatting and comments do not make a difference', () {
      final reformatted = _base
          .replaceAll('final int x;', '// note\n  final   int   x ;')
          .replaceAll('\n\n', '\n');

      expect(
        _signature(reformatted).firstDifference(_signature(_base)),
        isNull,
      );
    });

    test('a changed declaration is reported with its name and location', () {
      final changed = _base.replaceAll('final int y;', 'final String y;');
      final difference = _signature(changed).firstDifference(_signature(_base));

      expect(difference!.declaration, 'B');
      expect(difference.location!.start, const Position(8, 1));
    });

    test('the first differing declaration wins', () {
      final changed = _base
          .replaceAll('final int x;', 'final String x;')
          .replaceAll('final int y;', 'final String y;');
      final difference = _signature(changed).firstDifference(_signature(_base));

      expect(difference!.declaration, 'A');
    });

    test('changed annotation names or arguments are differences', () {
      final arguments = _base.replaceAll(
        '@JsonSerializable()',
        '@JsonSerializable(explicitToJson: true)',
      );
      final renamed = _base.replaceAll('@freezed', '@Freezed()');

      expect(
        _signature(arguments).firstDifference(_signature(_base))!.declaration,
        'A',
      );
      expect(
        _signature(renamed).firstDifference(_signature(_base))!.declaration,
        'B',
      );
    });

    test('an added declaration is a difference', () {
      const added = '$_base\n@JsonSerializable()\nclass C {}\n';
      final difference = _signature(added).firstDifference(_signature(_base));

      expect(difference!.declaration, 'C');
      expect(difference.location, isNotNull);
    });

    test('a removed declaration is named, with no location', () {
      final removed = _base.substring(0, _base.indexOf('@freezed'));
      final difference = _signature(removed).firstDifference(_signature(_base));

      expect(difference!.declaration, 'B');
      expect(difference.location, isNull);
    });

    test('only the list of parts differing has no declaration and no '
        'location', () {
      final more = _base.replaceFirst(
        "part 'a.g.dart';",
        "part 'a.g.dart';\npart 'a.freezed.dart';",
      );
      final difference = _signature(more).firstDifference(_signature(_base));

      expect(difference, isNotNull);
      expect(difference!.declaration, isNull);
      expect(difference.location, isNull);
    });

    test('no base: the first annotated declaration, with no location', () {
      final difference = _signature(_base).firstDifference(null);

      expect(difference!.declaration, 'A');
      expect(difference.location, isNull);
    });

    test('no base and no declarations still differ', () {
      final difference = _signature("part 'a.g.dart';").firstDifference(null);

      expect(difference, isNotNull);
      expect(difference!.declaration, isNull);
    });

    test('declarations that share a name are matched by occurrence', () {
      const getterAndSetter = '''
class V {
  @a List<int> get xs => [];
  @b set xs(List<int> v) {}
}
''';
      final changed = getterAndSetter.replaceAll(
        'set xs(List<int> v) {}',
        'set xs(List<int> v) { x = v; }',
      );
      final difference = _signature(changed)
          .firstDifference(_signature(getterAndSetter));

      expect(difference!.declaration, 'V.xs');
      expect(difference.location!.start, const Position(3, 3));
    });
  });
}

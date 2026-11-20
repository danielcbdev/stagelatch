import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';
import 'package:test/test.dart';

DartFileFacts _facts(String source) =>
    const SyntacticFacts().extract(source, RepoPath('lib/a.dart'));

List<AnnotatedDeclaration> _declarations(String source) =>
    _facts(source).annotatedDeclarations;

/// `name: annotations` for each declaration, for compact assertions.
List<String> _summary(String source) => [
  for (final d in _declarations(source))
    '${d.name}: ${d.annotations.join('+')}',
];

String _hashOf(String source) => _declarations(source).single.tokenHash;

void main() {
  group('token hash', () {
    test('is the SHA-256 of the lexemes joined by one space', () {
      // `@ a class A { }`
      expect(
        _hashOf('@a class A {}'),
        '8cf72cf3877fb4cd518557e99f22cf53534cae570347c1b35dafcfc13683845e',
      );
    });

    test('ignores whitespace and comments', () {
      expect(
        _hashOf('@JsonSerializable()\nclass A { final int x; A(this.x); }'),
        _hashOf(
          '@JsonSerializable()\nclass A {\n  // note\n  final int x;\n'
          '  /* more */ A(this.x);\n}',
        ),
      );
    });

    test('changes when a field is added, renamed or retyped', () {
      final before = _hashOf('@a class A { final int x; }');

      expect(
        _hashOf('@a class A { final int x; final int y; }'),
        isNot(before),
      );
      expect(_hashOf('@a class A { final int z; }'), isNot(before));
      expect(_hashOf('@a class A { final String x; }'), isNot(before));
    });

    test('changes when an annotation argument changes', () {
      expect(
        _hashOf("@JsonKey(name: 'a') final int x;"),
        isNot(_hashOf("@JsonKey(name: 'b') final int x;")),
      );
    });

    test('covers the whole declaration, parameters and bodies included', () {
      expect(
        _hashOf('@a void f(int x) { print(x); }'),
        isNot(_hashOf('@a void f(int x) { print(x + 1); }')),
      );
    });
  });

  group('which declarations', () {
    test('annotations are names without arguments, sorted; excluded '
        'annotations do not count', () {
      final declaration = _declarations(
        '@immutableRecord @JsonSerializable(explicitToJson: true) @override\n'
        "@Deprecated('x')\nclass A {}",
      ).single;

      expect(declaration.annotations, ['JsonSerializable', 'immutableRecord']);
    });

    test('a declaration with only excluded annotations is not annotated', () {
      expect(
        _declarations(
          '@override @protected @visibleForTesting @immutable @deprecated '
          "@Deprecated('x') class A { @override void f() {} }",
        ),
        isEmpty,
      );
    });

    test('annotation names are written as in the source', () {
      expect(_summary('@pkg.Annotation() @Foo.bar() @Baz<int>() class A {}'), [
        'A: Baz+Foo.bar+pkg.Annotation',
      ]);
    });

    test('annotated members are named Class.member', () {
      expect(
        _summary(r'''
@JsonSerializable()
class Order {
  const Order(this.id);
  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
  @JsonKey(name: 'order_id')
  final int id;
  @override
  String toString() => 'x';
  @JsonKey(includeToJson: false) Map<String, dynamic> toJson() => {};
}
'''),
        [
          'Order: JsonSerializable',
          'Order.id: JsonKey',
          'Order.toJson: JsonKey',
        ],
      );
    });

    test('constructors are Class.named or Class.new; enum constants '
        'Enum.value', () {
      expect(
        _summary('''
class A {
  @inject A();
  @inject A.named();
  @inject factory A.make() => A();
}
@JsonEnum()
enum Color {
  @JsonValue('r') red,
  green,
  @JsonValue('b') blue;
  const Color();
  @JsonKey(name: 'x') int get v => 1;
}
'''),
        [
          'A.new: inject',
          'A.named: inject',
          'A.make: inject',
          'Color: JsonEnum',
          'Color.red: JsonValue',
          'Color.blue: JsonValue',
          'Color.v: JsonKey',
        ],
      );
    });

    test('mixins, extensions and extension types have members too', () {
      expect(
        _summary('''
mixin M { @a void f() {} }
extension E on int { @b int get g => 1; }
extension on int { @c int get h => 1; }
extension type T(int i) { @d int get j => i; }
'''),
        ['M.f: a', 'E.g: b', '<unnamed>.h: c', 'T.j: d'],
      );
    });

    test('top-level variables, functions and typedefs', () {
      expect(
        _summary('''
@a final Map<String, List<int>> table = {'a': [1]};
@b Future<void> run() async { final f = () { return 1; }; }
@c int top = 2, other = 3;
@d typedef F = void Function();
@e typedef void G(int x);
@f class H = Object with M;
'''),
        ['table: a', 'run: b', 'top: c', 'F: d', 'G: e', 'H: f'],
      );
    });

    test('methods with type parameters are found by their name', () {
      expect(
        _summary(r'''
extension P on X {
  @optionalTypeArgs
  TResult map<TResult extends Object?>(TResult Function(A value) $default,) {
    return $default(this);
  }
}
'''),
        ['P.map: optionalTypeArgs'],
      );
    });

    test('operators are named by their symbol', () {
      expect(
        _summary('''
class V {
  @a bool operator ==(Object o) => true;
  @b int operator [](int i) => i;
  @c void operator []=(int i, int v) {}
}
'''),
        ['V.==: a', 'V.[]: b', 'V.[]=: c'],
      );
    });

    test('generics that close with >> do not confuse the header', () {
      expect(
        _summary('''
class V<T extends List<List<int>>> {
  @a List<List<int>> get xs => [];
  @b set xs(List<List<int>> v) {}
}
'''),
        ['V.xs: a', 'V.xs: b'],
      );
    });

    test('a constructor initializer list with brace literals ends at its '
        'body', () {
      expect(
        _summary('''
@injectable
class A {
  @c A(this.x) : y = {1: 2}, z = const {3} {
    print(x);
  }
  final int x;
  @d final Map<int, int> y;
}
'''),
        ['A: injectable', 'A.new: c', 'A.y: d'],
      );
    });

    test('freezed: redirecting factories with annotated parameters', () {
      expect(
        _summary(r'''
@freezed
sealed class Shape with _$Shape {
  const factory Shape.circle(@Default(1) double r) = Circle;
  const factory Shape.square(double side) = Square;
}
'''),
        ['Shape: freezed'],
      );
    });

    test('directive annotations are not declarations', () {
      expect(
        _declarations(
          "@Skip('x')\nlibrary;\n@a import 'b.dart';\n@c part 'd.dart';",
        ),
        isEmpty,
      );
    });

    test('code after a declaration is still found, in order', () {
      expect(_summary('@a class A {}\nclass B {}\n@b class C {}'), [
        'A: a',
        'C: b',
      ]);
    });
  });

  group('location', () {
    test('runs from the first annotation to the end of the last', () {
      final declaration = _declarations('\n  @A()\n  @B\nclass C {}\n').single;

      expect(
        declaration.location,
        Location(
          RepoPath('lib/a.dart'),
          const Position(2, 3),
          const Position(3, 5),
        ),
      );
    });

    test('a member is located at its own first annotation', () {
      final member = _declarations('class A {\n  @a int x = 1;\n}').single;

      expect(member.location.start, const Position(2, 3));
    });
  });

  group('files the lexer cannot read', () {
    test(
      'are not well formed, have no declarations, keep their directives',
      () {
        final facts = _facts(
          "import 'b.dart';\n@a class A { final x = 'oops;\n",
        );

        expect(facts.isWellFormed, isFalse);
        expect(facts.annotatedDeclarations, isEmpty);
        expect(facts.directives.single.uri, 'b.dart');
      },
    );

    test('unpaired brackets are not well formed', () {
      expect(_facts('@a class A { void f() { }').isWellFormed, isFalse);
      expect(_facts('@a class A { void f( }').isWellFormed, isFalse);
    });

    test('a readable file is well formed', () {
      expect(_facts('@a class A {}').isWellFormed, isTrue);
      expect(_facts('').isWellFormed, isTrue);
    });
  });
}

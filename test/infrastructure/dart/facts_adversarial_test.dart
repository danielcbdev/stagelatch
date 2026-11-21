import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';
import 'package:test/test.dart';

/// Hostile inputs for the fact extractor (security rule S6): 1 MiB of each
/// shape must finish, without recursion on the input overflowing the stack.
/// The timeout is far above what a linear scan needs and well below what a
/// quadratic one would take, so a regression fails instead of hanging.
void main() {
  const mib = 1024 * 1024;
  const timeout = Timeout(Duration(seconds: 60));

  final shapes = <String, String>{
    '"(" repeated': '(' * mib,
    '"{" repeated': '{' * mib,
    '"[" repeated': '[' * mib,
    '"}" repeated': '}' * mib,
    'nested interpolation': r"'${" * (mib ~/ 4),
    '"/*" repeated (nested comments)': '/*' * (mib ~/ 2),
    'one unterminated string': "'${'a' * mib}",
    'one identifier': 'a' * mib,
    '@a repeated': '@a ' * (mib ~/ 3),
    'class bodies with annotated members': 'class A { @a int x; ' * (mib ~/ 18),
    'initializer lists': 'A() : x = ' * (mib ~/ 10),
    'annotation arguments': '@a(' * (mib ~/ 3),
    // Balanced shapes: these are the ones that would cost the square of the
    // file if a call or declaration copied what encloses it.
    'balanced nested groups': "group('a', () {" * 30000 + '});' * 30000,
    'balanced nested test calls': 'test(' * 100000 + ')' * 100000,
    'balanced nested groups with long descriptions':
        "group('${'x' * 100}', () {" * 6000 + '});' * 6000,
    'huge non-literal description inside nested calls':
        'test(' * 10000 + 'x' * 500000 + ')' * 10000,
    'balanced parentheses': '(' * 400000 + ')' * 400000,
    'balanced annotated classes': '@a class A {' * 40000 + '}' * 40000,
    'balanced annotation arguments': '@a(' * 100000 + ')' * 100000,
  };

  for (final MapEntry(key: name, value: source) in shapes.entries) {
    test('1 MiB of $name finishes', () {
      final facts = const SyntacticFacts().extract(source, RepoPath('a.dart'));

      expect(facts, isNotNull);
    }, timeout: timeout);
  }

  test('a call remembers at most the 64 outermost groups', () {
    final opening = "group('g', () {" * 100;
    final source =
        "void main() {\n${opening}test('t', () {});${'});' * 100}\n}\n";
    final calls = const SyntacticFacts()
        .extract(source, RepoPath('a_test.dart'))
        .testCalls;

    expect(calls, hasLength(101));
    expect(calls.last.groups, hasLength(64));
    expect(calls[99].groups, hasLength(64));
    expect(calls[10].groups, hasLength(10));
  });

  test('the source text of a description is cut at 4,096 characters', () {
    final source = "void main() { test('${'x' * 10000}' + y, () {}); }";
    final call = const SyntacticFacts()
        .extract(source, RepoPath('a_test.dart'))
        .testCalls
        .single;

    expect(call.description, hasLength(4096));
    expect(call.description, startsWith("'xxx"));
  });

  test('every prefix of a real file is extracted without throwing', () {
    const source = r'''
import 'a.dart';
@JsonSerializable(explicitToJson: true)
class Order {
  const Order(this.id) : x = {1: 2};
  @JsonKey(name: 'order_id')
  final int id;
  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson('${json['a']}');
}
@JsonEnum()
enum Color { @JsonValue('r') red, green; }
''';

    for (var end = 0; end <= source.length; end++) {
      expect(
        () => const SyntacticFacts().extract(
          source.substring(0, end),
          RepoPath('a.dart'),
        ),
        returnsNormally,
        reason: 'prefix of $end characters',
      );
    }
  });

  test('a file of unrelated binary-looking text does not throw', () {
    final noise = String.fromCharCodes([
      for (var i = 0; i < 20000; i++) (i * 7919) % 0xFFFF,
    ]);

    expect(
      () => const SyntacticFacts().extract(noise, RepoPath('a.dart')),
      returnsNormally,
    );
  });
}

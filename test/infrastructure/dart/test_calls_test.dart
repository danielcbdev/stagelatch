import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart';
import 'package:test/test.dart';

DartFileFacts _facts(String source, {Set<String>? functions}) =>
    (functions == null
            ? const SyntacticFacts()
            : SyntacticFacts(testFunctions: functions))
        .extract(source, RepoPath('test/a_test.dart'));

List<TestCall> _calls(String source, {Set<String>? functions}) =>
    _facts(source, functions: functions).testCalls;

void main() {
  test('calls are collected with their enclosing groups', () {
    final calls = _calls(
      "group('cart', () { test('adds', () {}, skip: true); });",
    );

    expect(calls.map((c) => c.function), ['group', 'test']);
    final test = calls.last;
    expect(test.groups, ['cart']);
    expect(test.description, 'adds');
    expect(test.skip, isNotNull);
    expect(test.solo, isNull);
    expect(calls.first.groups, isEmpty);
    expect(calls.first.description, 'cart');
  });

  test('groups nest, outermost first, and end with their call', () {
    final calls = _calls('''
void main() {
  group('outer', () {
    group('inner', () {
      test('deep', () {});
    });
    test('shallow', () {});
  });
  test('top', () {});
}
''');

    expect(
      [for (final c in calls) '${c.description}: ${c.groups.join('/')}'],
      [
        'outer: ',
        'inner: outer',
        'deep: outer/inner',
        'shallow: outer',
        'top: ',
      ],
    );
  });

  test('solo: false and skip: false or null are not set', () {
    final calls = _calls('''
void main() {
  test('a', () {}, solo: false);
  test('b', () {}, skip: false);
  test('c', () {}, skip: null);
  test('d', () {}, solo: true);
  test('e', () {}, skip: true);
  test('f', () {}, skip: 'because');
  test('g', () {}, skip: someFlag);
  test('h', () {}, solo: shouldSolo);
}
''');

    expect(
      [
        for (final c in calls)
          '${c.description}: ${c.solo != null} ${c.skip != null}',
      ],
      [
        'a: false false',
        'b: false false',
        'c: false false',
        'd: true false',
        'e: false true',
        'f: false true',
        'g: false true',
        'h: true false',
      ],
    );
  });

  test('the location of the call, of solo and of skip', () {
    final call = _calls("test('a', () {}, solo: true, skip: 'x');").single;

    expect(
      call.location,
      Location(
        RepoPath('test/a_test.dart'),
        const Position(1, 1),
        const Position(1, 40),
      ),
    );
    expect(call.solo!.start, const Position(1, 18));
    expect(call.solo!.end, const Position(1, 28));
    expect(call.skip!.start, const Position(1, 30));
    expect(call.skip!.end, const Position(1, 39));
  });

  test('a @Skip annotation on the library or the enclosing function counts '
      'as skip', () {
    final library = _calls(
      "@Skip('flaky')\nlibrary;\n\nvoid main() { test('a', () {}); }",
    ).single;
    final function = _calls('''
@Skip('later')
void main() { test('a', () {}); }
void other() { test('b', () {}); }
''');

    expect(library.skip!.start, const Position(1, 1));
    expect(library.skip!.end, const Position(1, 15));
    expect(function.first.skip!.start, const Position(1, 1));
    expect(function.last.skip, isNull);
  });

  test('a call own skip argument wins over an annotation', () {
    final call = _calls(
      "@Skip('x')\nlibrary;\nvoid main() { test('a', () {}, skip: 'own'); }",
    ).single;

    expect(call.skip!.start.line, 3);
  });

  test('a non-literal description uses its source text', () {
    final calls = _calls(r'''
void main() {
  test('adds $n', () {});
  test('plain ${n + 1} text', () {});
  test(name, () {});
  test('a' + b, () {});
}
''');

    expect(calls.map((c) => c.description), [
      r"'adds $n'",
      r"'plain ${n + 1} text'",
      'name',
      "'a' + b",
    ]);
  });

  test('escapes, raw strings, adjacent literals and multi-line literals give '
      'the literal value', () {
    final calls = _calls(
      r'''
void main() {
  test('it\'s ' 'two', () {});
  test("tab\there", () {});
  test(r'raw \n $x', () {});
  test('é \x41 \u{1F600}', () {});
  test('a\
b', () {});
  test(\'\'\'
multi
line\'\'\', () {});
}
'''
          .replaceAll(r"\'\'\'", "'''"),
    );

    expect(calls.map((c) => c.description), [
      "it's two",
      'tab\there',
      r'raw \n $x',
      'é A \u{1F600}',
      'ab',
      'multi\nline',
    ]);
  });

  test('only functions named in tests.functions are collected', () {
    const source = '''
void main() {
  test('a', () {});
  testWidgets('b', (t) async {});
  testGoldens('c', (t) async {});
  group('d', () {});
}
''';

    expect(_calls(source).map((c) => c.function), [
      'test',
      'testWidgets',
      'group',
    ]);
    expect(_calls(source, functions: {'testGoldens'}).map((c) => c.function), [
      'testGoldens',
    ]);
  });

  test('qualified calls, declarations and named arguments are not calls', () {
    final calls = _calls('''
void test(String name) {}
void main() {
  obj.test('x');
  obj?.test('x');
  obj..test('x');
  helper(test: 1);
  Future<void> test2() async {}
  await test('y', () {});
  return test('z', () {});
}
''');

    expect(calls.map((c) => c.description), ['y', 'z']);
  });

  test('a call with no positional argument is not collected', () {
    expect(_calls('void main() { test(skip: true); }'), isEmpty);
  });

  test('calls inside helpers, methods and closures are collected', () {
    final calls = _calls('''
void helper() { test('in helper', () {}); }
class Suite {
  void run() { group('in method', () { test('nested', () {}); }); }
}
final registered = () { test('in closure', () {}); };
''');

    expect(calls.map((c) => c.description), [
      'in helper',
      'in method',
      'nested',
      'in closure',
    ]);
  });

  test('a file the lexer cannot read has no calls and is not well formed', () {
    final facts = _facts("void main() { test('a', () {});\n");

    expect(facts.isWellFormed, isFalse);
    expect(facts.testCalls, isEmpty);
  });

  test('with no test functions configured nothing is collected', () {
    expect(_calls("void main() { test('a', () {}); }", functions: {}), isEmpty);
  });
}

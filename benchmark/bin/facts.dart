/// Measures the two fact extractors of ADR-0017 on the corpus.
///
/// `dart run benchmark/bin/facts.dart <mode>`
///
/// - `parse` / `scan`: time one extractor in a fresh process, first on the
///   10 files of scenario s10 (cold, as a commit would ask), then on the
///   whole corpus.
/// - `compare`: run both over every `.dart` file and list each file where
///   they disagree.
/// - `edges`: run both over the hand-written edge cases.
/// - `adversarial`: time the scanner and the parser on hostile inputs.
/// - `fuzz`: mutate corpus files into broken ones; the scanner must never
///   throw, and its lexical check is compared with the parser's errors.
library;

import 'dart:io';
import 'dart:math';

import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/facts_model.dart';
import 'package:stagelatch_bench/facts_parse.dart';
import 'package:stagelatch_bench/facts_scanner.dart';
import 'package:stagelatch_bench/input.dart';
import 'package:stagelatch_bench/proc.dart';
import 'package:stagelatch_bench/workspace.dart';

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'compare' : args.first;
  switch (mode) {
    case 'edges':
      _edges();
    case 'adversarial':
      _adversarial(args.skip(1).toList());
    case 'fuzz':
      await _fuzz();
    case 'parse' || 'scan' || 'compare':
      await _corpus(mode);
    default:
      stderr.writeln('Usage: facts parse|scan|compare|edges|adversarial|fuzz');
      exitCode = 64;
  }
}

Future<void> _fuzz() async {
  final ws = BenchWorkspace.find();
  final corpus = Corpus.load(ws);
  final listing = await run('git', [
    'ls-tree',
    '-r',
    '-z',
    corpus.sha,
  ], workingDirectory: ws.corpusDir);
  final blobs = [
    for (final record in listing.split('\x00'))
      if (record.endsWith('.dart')) record.split(' ')[2].split('\t').first,
  ];
  final sources = await readBlobs(ws.corpusDir, blobs.take(400).toList());
  final random = Random(2026);
  var total = 0;
  var threw = 0;
  var parserErrors = 0;
  var scannerFlagged = 0;
  var both = 0;
  for (final source in sources) {
    if (source.length < 50) continue;
    final cut = random.nextInt(source.length);
    final brace = source.indexOf('}', random.nextInt(source.length));
    final paren = source.indexOf(')', random.nextInt(source.length));
    final quote = random.nextInt(source.length);
    final variants = [
      source.substring(0, cut),
      if (brace >= 0) source.replaceRange(brace, brace + 1, ''),
      if (paren >= 0) source.replaceRange(paren, paren + 1, ''),
      "${source.substring(0, quote)}'${source.substring(quote)}",
    ];
    for (final v in variants) {
      total++;
      try {
        factsByScanner(v);
      } on Object {
        threw++;
      }
      final hasError = parsedHasErrors(v);
      final flagged = !lex(v).balanced;
      if (hasError) parserErrors++;
      if (flagged) scannerFlagged++;
      if (hasError && flagged) both++;
    }
  }
  stdout
    ..writeln('mutated files: $total, scanner threw: $threw')
    ..writeln('parser reports syntax errors: $parserErrors')
    ..writeln('scanner lexical check flags: $scannerFlagged')
    ..writeln('both: $both');
}

Future<void> _corpus(String mode) async {
  final ws = BenchWorkspace.find();
  final corpus = Corpus.load(ws);
  final listing = await run('git', [
    'ls-tree',
    '-r',
    '-z',
    corpus.sha,
  ], workingDirectory: ws.corpusDir);
  final entries = [
    for (final record in listing.split('\x00'))
      if (record.endsWith('.dart'))
        (
          blob: record.split(' ')[2].split('\t').first,
          path: record.substring(record.indexOf('\t') + 1),
        ),
  ];
  final sources = await readBlobs(ws.corpusDir, [
    for (final e in entries) e.blob,
  ]);
  stdout.writeln('files: ${entries.length}');

  final s10 = _s10Files();
  final tenIndexes = [
    for (var i = 0; i < entries.length; i++)
      if (s10.any(entries[i].path.endsWith)) i,
  ];
  stdout.writeln('s10 files found: ${tenIndexes.length}');

  if (mode == 'parse' || mode == 'scan') {
    final FactsResult? Function(String) f = mode == 'parse'
        ? factsByParser
        : factsByScanner;
    final cold = Stopwatch()..start();
    tenIndexes.map((i) => sources[i]).forEach(f);
    cold.stop();
    stdout.writeln(
      '$mode: 10 files (s10, cold) ${cold.elapsedMicroseconds / 1000} ms',
    );
    final all = Stopwatch()..start();
    sources.forEach(f);
    all.stop();
    stdout.writeln(
      '$mode: ${entries.length} files ${all.elapsedMilliseconds} ms',
    );
    return;
  }

  final parsed = [for (final s in sources) factsByParser(s)!];
  final scanned = [for (final s in sources) factsByScanner(s)!];
  var disagree = 0;
  var decls = 0;
  var calls = 0;
  for (var i = 0; i < entries.length; i++) {
    decls += parsed[i].declarations.length;
    calls += parsed[i].calls.length;
    final a = parsed[i].canonical;
    final b = scanned[i].canonical;
    if (a.join('\n') == b.join('\n')) continue;
    disagree++;
    stdout.writeln('disagree: ${entries[i].path}');
    for (final x in a.where((x) => !b.contains(x)).take(3)) {
      stdout.writeln('    P only: ${_clip(x)}');
    }
    for (final x in b.where((x) => !a.contains(x)).take(3)) {
      stdout.writeln('    S only: ${_clip(x)}');
    }
  }
  final broken = sources.where(parsedHasErrors).length;
  var shown = 0;
  for (var i = 0; i < sources.length && shown < 4; i++) {
    final e = firstParseError(sources[i]);
    if (e != null) {
      shown++;
      stdout.writeln('  parser error in ${entries[i].path}: $e');
    }
  }
  final unbalanced = sources.where((s) => !lex(s).balanced).length;
  stdout
    ..writeln('files with syntax errors (parser): $broken')
    ..writeln('files the lexical check flags (scanner): $unbalanced')
    ..writeln('annotated declarations (reference): $decls')
    ..writeln('test calls (reference): $calls')
    ..writeln('disagreeing files: $disagree of ${entries.length}');
}

String _clip(String s) => s.length > 220 ? '${s.substring(0, 220)}...' : s;

List<String> _s10Files() {
  final patch = File(
    '${BenchWorkspace.find().repoRoot}/benchmark/scenarios/s10/staged.patch',
  ).readAsLinesSync();
  return [
    for (final line in patch)
      if (line.startsWith('+++ b/')) line.substring(6),
  ];
}

const _edgeCases = <String, String>{
  'interpolated description': r'''
void main() {
  test('adds $n', () {});
  test('plain ${n + 1} text', () {});
}
''',
  'solo and skip arguments': '''
void main() {
  test('a', () {}, solo: true);
  test('b', () {}, solo: false);
  test('c', () {}, skip: true);
  test('d', () {}, skip: false);
  test('e', () {}, skip: null);
  test('f', () {}, skip: 'reason');
  test('g', () {}, skip: someFlag);
}
''',
  'nested groups': '''
void main() {
  group('outer', () {
    group('inner', () {
      test('deep', () {}, skip: true);
    });
    test('shallow', () {});
  });
}
''',
  'library skip': '''
@Skip('flaky')
library;

void main() { test('a', () {}); }
''',
  'function skip': '''
@Skip('later')
void main() { test('a', () {}); }
void other() { test('b', () {}); }
''',
  'not a test call': '''
void test(String name) {}
void main() { obj.test('x'); helper(test: 1); await test('y', () {}); }
''',
  'adjacent and escaped strings': '''
void main() {
  test('it\\'s ' 'two', () {});
  test("tab\\there", () {});
  test(r'raw \$x', () {});
  test(\'\'\'
  multi
  line\'\'\', () {});
}
''',
  'json_serializable': r'''
@JsonSerializable(explicitToJson: true)
class Order {
  const Order(this.id);
  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
  @JsonKey(name: 'order_id')
  final int id;
  @override
  String toString() => 'x';
  Map<String, dynamic> toJson() => _$OrderToJson(this);
}
''',
  'freezed and enums': r'''
@freezed
sealed class Shape with _$Shape {
  const factory Shape.circle(@Default(1) double r) = Circle;
  const factory Shape.square(double side) = Square;
}

@JsonEnum()
enum Color {
  @JsonValue('r') red,
  green,
  @JsonValue('b') blue;
  const Color();
  @JsonKey(name: 'x') int get v => 1;
}
''',
  'constructor with initializer list and braces': '''
@injectable
class A {
  A(this.x) : y = {1: 2}, z = const {3} {
    print(x);
  }
  final int x;
  final Map<int, int> y;
  final Set<int> z;
}
''',
  'variables and functions': '''
@Deprecated('x')
@pragma('vm:entry-point')
final Map<String, List<int>> table = {'a': [1]};

@Injectable()
Future<void> run() async {
  final a = () { return 1; };
}

@Default(1) int top = 2;
''',
  'generics and operators': '''
@immutable
class V<T extends List<List<int>>> {
  @protected
  bool operator ==(Object o) => true;
  @JsonKey()
  List<List<int>> get xs => [];
  @visibleForTesting
  set xs(List<List<int>> v) {}
}
''',
};

void _edges() {
  var bad = 0;
  for (final MapEntry(key: name, value: source) in _edgeCases.entries) {
    final a = factsByParser(source)!.canonical;
    final b = factsByScanner(source)!.canonical;
    if (a.join('\n') == b.join('\n')) {
      stdout.writeln('agree: $name (${a.length - 1} facts)');
    } else {
      bad++;
      stdout.writeln('DISAGREE: $name');
      for (final x in a.where((x) => !b.contains(x))) {
        stdout.writeln('    P only: ${_clip(x)}');
      }
      for (final x in b.where((x) => !a.contains(x))) {
        stdout.writeln('    S only: ${_clip(x)}');
      }
    }
  }
  stdout.writeln('edge cases disagreeing: $bad of ${_edgeCases.length}');
}

void _adversarial(List<String> args) {
  const mib = 1024 * 1024;
  final inputs = <String, String>{
    '1 MiB of "(" (deep nesting)': '(' * mib,
    '1 MiB of "{" (deep nesting)': '{' * mib,
    '1 MiB of "[" (deep nesting)': '[' * mib,
    '1 MiB of nested interpolation': r"'${" * (mib ~/ 4),
    '1 MiB of "/*" (nested comments)': '/*' * (mib ~/ 2),
    '1 MiB unterminated string': "'${'a' * mib}",
    '1 MiB identifier': 'a' * mib,
    '1 MiB of annotations': '@a ' * (mib ~/ 3),
    '1 MiB of "test(" calls': 'test(' * (mib ~/ 5),
    '1 MiB of "group(\'a\', () {"': "group('a', () {" * (mib ~/ 15),
    '1 MiB of "class A {"': 'class A { @a int x; ' * (mib ~/ 18),
    '1 MiB of "A() : x = "': 'A() : x = ' * (mib ~/ 10),
  };
  final names = inputs.keys.toList();
  if (args.isEmpty) {
    for (var i = 0; i < names.length; i++) {
      stdout.writeln('$i ${names[i]}');
    }
    return;
  }
  final name = names[int.parse(args[0])];
  final source = inputs[name]!;
  final result = args[1] == 'scan'
      ? _time(() => factsByScanner(source))
      : _time(() => factsByParser(source));
  stdout.writeln('$name | ${args[1]} | $result');
}

String _time(Object? Function() f) {
  final watch = Stopwatch()..start();
  try {
    f();
    return '${watch.elapsedMilliseconds} ms';
  } on Object catch (e) {
    final text = e.toString().split('\n').first;
    return 'FAILED after ${watch.elapsedMilliseconds} ms: '
        '${text.length > 80 ? text.substring(0, 80) : text}';
  }
}

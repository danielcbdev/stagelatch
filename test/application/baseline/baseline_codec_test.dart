import 'dart:convert';

import 'package:stagelatch/src/application/baseline/baseline.dart';
import 'package:stagelatch/src/application/baseline/baseline_codec.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:test/test.dart';

final String _a = 'a' * 64;
final String _b = 'b' * 64;

BaselineEntry _entry(String rule, String path, String fingerprint, int count) =>
    BaselineEntry(
      rule: RuleId.parse(rule),
      path: RepoPath(path),
      fingerprint: fingerprint,
      count: count,
    );

Matcher _configError(String message) => throwsA(
  isA<ConfigException>().having(
    (error) => error.message,
    'message',
    contains(message),
  ),
);

String _document({Object? version = 1, Object? entries = const []}) =>
    jsonEncode({'version': version, 'entries': entries});

Map<String, Object?> _raw({
  Object? rule = 'pubspec/path-dependency',
  Object? path = 'pubspec.yaml',
  Object? fingerprint,
  Object? count = 1,
}) => {
  'rule': rule,
  'path': path,
  'fingerprint': fingerprint ?? _a,
  'count': count,
};

void main() {
  group('encodeBaseline', () {
    test('sorts by path, rule and fingerprint, indents and ends with a '
        'newline', () {
      final baseline = Baseline([
        _entry('pubspec/path-dependency', 'pubspec.yaml', _b, 1),
        _entry('analyze/unused_import', 'lib/z.dart', _a, 2),
        _entry('analyze/unused_import', 'lib/a.dart', _b, 1),
        _entry('analyze/dead_code', 'lib/a.dart', _b, 1),
        _entry('analyze/dead_code', 'lib/a.dart', _a, 3),
      ]);

      expect(encodeBaseline(baseline), '''
{
  "version": 1,
  "entries": [
    {
      "rule": "analyze/dead_code",
      "path": "lib/a.dart",
      "fingerprint": "$_a",
      "count": 3
    },
    {
      "rule": "analyze/dead_code",
      "path": "lib/a.dart",
      "fingerprint": "$_b",
      "count": 1
    },
    {
      "rule": "analyze/unused_import",
      "path": "lib/a.dart",
      "fingerprint": "$_b",
      "count": 1
    },
    {
      "rule": "analyze/unused_import",
      "path": "lib/z.dart",
      "fingerprint": "$_a",
      "count": 2
    },
    {
      "rule": "pubspec/path-dependency",
      "path": "pubspec.yaml",
      "fingerprint": "$_b",
      "count": 1
    }
  ]
}
''');
    });

    test('an empty baseline is an empty list', () {
      expect(
        encodeBaseline(Baseline.empty),
        '{\n  "version": 1,\n  "entries": []\n}\n',
      );
    });

    test('is independent of the order of the entries', () {
      final one = _entry('a/b', 'x', _a, 1);
      final two = _entry('a/b', 'y', _a, 1);

      expect(
        encodeBaseline(Baseline([one, two])),
        encodeBaseline(Baseline([two, one])),
      );
    });
  });

  group('decodeBaseline', () {
    test('decode(encode(x)) gives x back', () {
      final baseline = Baseline([
        _entry('analyze/unused_import', 'lib/a.dart', _a, 2),
        _entry('pubspec/path-dependency', 'pubspec.yaml', _b, 1),
      ]);

      expect(
        decodeBaseline(encodeBaseline(baseline)).entries,
        baseline.entries,
      );
    });

    test('invalid JSON is a config error', () {
      expect(() => decodeBaseline('{'), _configError('not valid JSON'));
    });

    test('anything but an object is a config error', () {
      expect(
        () => decodeBaseline('[]'),
        _configError('expected a JSON object'),
      );
    });

    test('an unknown version is a config error', () {
      expect(
        () => decodeBaseline(_document(version: 2)),
        _configError('unsupported version 2; expected 1.'),
      );
      expect(
        () => decodeBaseline('{"entries": []}'),
        _configError('unsupported version null'),
      );
    });

    test('entries must be a list', () {
      expect(
        () => decodeBaseline(_document(entries: 'x')),
        _configError('"entries" must be a list'),
      );
    });

    test('a malformed entry names its index', () {
      expect(
        () => decodeBaseline(_document(entries: [_raw(), 3])),
        _configError('entry 1 is not an object'),
      );
      expect(
        () => decodeBaseline(_document(entries: [_raw(rule: 7)])),
        _configError('entry 0 needs a string "rule"'),
      );
      expect(
        () => decodeBaseline(_document(entries: [_raw(fingerprint: 'abc')])),
        _configError('entry 0 needs a "fingerprint" of 64 hexadecimal digits'),
      );
      expect(
        () => decodeBaseline(_document(entries: [_raw(count: 0)])),
        _configError('entry 0 needs a positive integer "count"'),
      );
      expect(
        () => decodeBaseline(_document(entries: [_raw(count: 1.5)])),
        _configError('entry 0 needs a positive integer "count"'),
      );
    });

    test('a rule that is not <check>/<rule> or an unclean path is a config '
        'error', () {
      expect(
        () => decodeBaseline(_document(entries: [_raw(rule: 'nope')])),
        _configError('entry 0:'),
      );
      expect(
        () => decodeBaseline(_document(entries: [_raw(path: '../up')])),
        _configError('entry 0:'),
      );
    });

    test('a repeated entry is a config error', () {
      expect(
        () => decodeBaseline(_document(entries: [_raw(), _raw()])),
        _configError('entry 1 repeats an earlier entry'),
      );
    });

    test('the exception points at the file when it is given', () {
      expect(
        () => decodeBaseline('{', path: RepoPath('.stagelatch/baseline.json')),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.toString(),
            'toString',
            startsWith('.stagelatch/baseline.json:1:1: Invalid baseline:'),
          ),
        ),
      );
    });
  });
}

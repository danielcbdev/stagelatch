import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/config/default_hooks.dart';
import 'package:stagelatch/src/application/config/settings.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../support/fake_check_catalog.dart';
import '../../support/fake_snapshot_files.dart';
import '../../support/fake_working_tree.dart';

typedef _Json = Map<String, Object?>;

final _Json _schema = jsonDecode(
  File('schema/stagelatch.schema.json').readAsStringSync(),
) as _Json;

/// The error the loader raises for [config], a JSON-compatible document
/// (which YAML reads as a flow mapping), or null when it accepts it.
Future<ConfigException?> _loadError(Object? config) async {
  try {
    await ConfigLoader(const StructuredDocuments(), FakeWorkingTree()).load(
      FakeSnapshotFiles({'stagelatch.yaml': jsonEncode(config)}),
      toolVersion: Version.parse('9.9.9'),
      catalog: FakeCheckCatalog.full(),
    );
    return null;
  } on ConfigException catch (error) {
    return error;
  }
}

/// The property schemas of the document, by dotted key.
Map<String, _Json> _properties() {
  final found = <String, _Json>{};
  void walk(_Json node, String prefix) {
    final properties = node['properties'] as _Json?;
    if (properties == null) return;
    for (final MapEntry(:key, :value) in properties.entries) {
      final property = value! as _Json;
      found['$prefix$key'] = property;
      walk(property, '$prefix$key.');
    }
  }

  walk(_schema, '');
  return found;
}

/// A document with [value] at the dotted [key].
Object? _at(String key, Object? value) {
  var result = value;
  for (final part in key.split('.').reversed) {
    result = {part: result};
  }
  return result;
}

/// The keys of the table in docs/specs/config.md, section 3.
Set<String> _specKeys() {
  final lines = File('docs/specs/config.md').readAsLinesSync();
  final start = lines.indexWhere((line) => line.startsWith('## 3. Keys'));
  final end = lines.indexWhere((line) => line.startsWith('## 4.'));
  return {
    for (final line in lines.sublist(start, end))
      if (RegExp(r'^\| `([^`]+)` \|').firstMatch(line) case final match?)
        match.group(1)!,
  };
}

/// The YAML of docs/specs/config.md, section 2, as plain data.
Object? _specExample() {
  final lines = File('docs/specs/config.md').readAsLinesSync();
  final start = lines.indexWhere((line) => line.startsWith('## 2.'));
  final open = lines.indexWhere((line) => line == '```yaml', start);
  final close = lines.indexWhere((line) => line == '```', open + 1);
  return _plain(loadYaml(lines.sublist(open + 1, close).join('\n')));
}

Object? _plain(Object? node) => switch (node) {
  final YamlMap map => {
    for (final MapEntry(:key, :value) in map.entries) '$key': _plain(value),
  },
  final YamlList list => [for (final item in list) _plain(item)],
  _ => node,
};

/// A minimal JSON Schema validator for the keywords the schema uses.
List<String> _validate(Object? value, _Json schema, String path) {
  final ref = schema[r'$ref'] as String?;
  if (ref != null) {
    final target = (_schema[r'$defs']! as _Json)[ref.split('/').last]! as _Json;
    return _validate(value, target, path);
  }
  final errors = <String>[];
  final type = schema['type'];
  if (type != null) {
    final types = type is List ? type.cast<String>() : [type as String];
    if (!types.any((name) => _isType(value, name))) {
      return ['$path: expected $types'];
    }
  }
  if (schema['enum'] case final List<Object?> allowed
      when !allowed.contains(value)) {
    errors.add('$path: not one of $allowed');
  }
  if (value is String) {
    if (schema['pattern'] case final String pattern
        when !RegExp(pattern).hasMatch(value)) {
      errors.add('$path: "$value" does not match $pattern');
    }
    if (schema['minLength'] case final int min when value.length < min) {
      errors.add('$path: shorter than $min');
    }
  }
  if (value is List<Object?>) {
    if (schema['items'] case final _Json items) {
      for (final (index, item) in value.indexed) {
        errors.addAll(_validate(item, items, '$path[$index]'));
      }
    }
  }
  if (value is Map<String, Object?>) {
    final properties = (schema['properties'] as _Json?) ?? const {};
    final additional = schema['additionalProperties'];
    final names = schema['propertyNames'] as _Json?;
    for (final MapEntry(:key, value: child) in value.entries) {
      if (names != null) errors.addAll(_validate(key, names, '$path/$key'));
      if (properties[key] case final _Json property) {
        errors.addAll(_validate(child, property, '$path.$key'));
      } else if (additional == false) {
        errors.add('$path: unknown key "$key"');
      } else if (additional is _Json) {
        errors.addAll(_validate(child, additional, '$path.$key'));
      }
    }
  }
  return errors;
}

bool _isType(Object? value, String type) => switch (type) {
  'string' => value is String,
  'null' => value == null,
  'object' => value is Map,
  'array' => value is List,
  'boolean' => value is bool,
  'integer' => value is int,
  'number' => value is num,
  _ => false,
};

/// The examples of [property] and its default, when it has one.
List<Object?> _samples(_Json property) => [
  ...property['examples']! as List<Object?>,
  if (property.containsKey('default')) property['default'],
];

void main() {
  final properties = _properties();

  group('shape', () {
    test('is draft 2020-12 and closed at every object', () {
      expect(
        _schema[r'$schema'],
        'https://json-schema.org/draft/2020-12/schema',
      );
      expect(_schema['additionalProperties'], isFalse);
      for (final MapEntry(:key, :value) in properties.entries) {
        if (value['properties'] != null) {
          expect(value['additionalProperties'], isFalse, reason: key);
        }
      }
    });

    test('every key has a description and an example', () {
      for (final MapEntry(:key, :value) in properties.entries) {
        expect(value['description'], isA<String>(), reason: key);
        expect(value['examples'], isNotEmpty, reason: key);
      }
      for (final MapEntry(:key, :value)
          in (_schema[r'$defs']! as _Json).entries) {
        final definition = value! as _Json;
        expect(definition['description'], isA<String>(), reason: key);
        expect(definition['examples'], isNotEmpty, reason: key);
      }
    });
  });

  group('agreement with the spec', () {
    test('the keys of the schema are the keys of config.md section 3', () {
      final leaves = {
        for (final MapEntry(:key, :value) in properties.entries)
          if (value['properties'] == null) key,
      };

      expect(leaves, _specKeys());
    });

    test('the schema accepts the full example of config.md section 2', () {
      expect(_validate(_specExample(), _schema, r'$'), isEmpty);
    });

    test('every example and every default validates against its own key', () {
      for (final MapEntry(:key, :value) in properties.entries) {
        for (final sample in _samples(value)) {
          expect(_validate(sample, value, key), isEmpty, reason: key);
        }
      }
    });
  });

  group('agreement with the loader', () {
    test('accepts every key with each example and default of the '
        'schema', () async {
      for (final MapEntry(:key, :value) in properties.entries) {
        if (value['properties'] != null) continue;
        for (final sample in _samples(value)) {
          expect(
            await _loadError(_at(key, sample)),
            isNull,
            reason: '$key: ${jsonEncode(sample)}',
          );
        }
      }
    });

    test('rejects an unknown key at the root and in every section, as the '
        'schema does', () async {
      expect(await _loadError({'pubspek': <String, Object?>{}}), isNotNull);
      for (final MapEntry(:key, :value) in properties.entries) {
        if (value['properties'] == null) continue;
        final config = _at('$key.forbid', true);
        expect(await _loadError(config), isNotNull, reason: key);
        expect(_validate(config, _schema, r'$'), isNotEmpty, reason: key);
      }
    });

    test('the top-level keys of the schema are the ones the loader reads', () {
      expect(properties.keys.where((key) => !key.contains('.')).toSet(), {
        'min_version',
        'hooks',
        'rules',
        'exclude',
        'sdk_path',
        'time_budget',
        'baseline',
        'format',
        'analyze',
        'codegen',
        'pubspec',
        'assets',
        'tests',
      });
    });

    test('hook names, scopes and severities match the code', () {
      final hooks = properties['hooks']!['properties']! as _Json;
      expect(hooks.keys.toSet(), hookNames.toSet());
      expect(properties['analyze.scope']!['enum'], [
        for (final scope in AnalyzeScope.values) scope.name,
      ]);
      expect((properties['analyze.fail_on']!['items']! as _Json)['enum'], [
        for (final severity in DiagnosticSeverity.values) severity.name,
      ]);
    });

    test('rule IDs and levels agree', () async {
      final rules = properties['rules']!;
      final names = rules['propertyNames']! as _Json;
      for (final valid in [
        'a/b',
        'pubspec/path-dependency',
        'analyze/unused_import',
      ]) {
        expect(_validate(valid, names, valid), isEmpty);
      }
      for (final invalid in ['nope', 'A/b', 'a/b/c', '/b']) {
        expect(_validate(invalid, names, invalid), isNotEmpty);
        expect(
          await _loadError({
            'rules': {invalid: 'error'},
          }),
          isNotNull,
        );
      }
      for (final level in ['error', 'warning', 'off']) {
        expect(
          await _loadError({
            'rules': {'tests/solo': level},
          }),
          isNull,
        );
      }
      final level = rules['additionalProperties']! as _Json;
      expect(_validate('fatal', level, 'level'), isNotEmpty);
      expect(
        await _loadError({
          'rules': {'tests/solo': 'fatal'},
        }),
        isNotNull,
      );
    });

    test('values the loader rejects, the schema rejects', () async {
      const bad = {
        'time_budget': '0',
        'assets.max_file_size': '500',
        'analyze.scope': 'everything',
        'min_version': 'next',
      };
      for (final MapEntry(:key, :value) in bad.entries) {
        expect(await _loadError(_at(key, value)), isNotNull, reason: key);
        expect(
          _validate(value, properties[key]!, key),
          isNotEmpty,
          reason: key,
        );
      }
    });
  });
}

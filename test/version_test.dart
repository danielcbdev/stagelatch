import 'dart:io';

import 'package:stagelatch/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('packageVersion equals the version in pubspec.yaml', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync());

    expect(pubspec, isA<YamlMap>());
    expect(packageVersion, (pubspec as YamlMap)['version']);
  });
}

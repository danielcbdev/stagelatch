/// The encoding of `DartFileFacts` in the cache (docs/specs/
/// dart-toolchain.md, section 6.1).
library;

import 'dart:convert';

import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// The version of the facts: one integer for the encoding below and for
/// what the extractor (the lexer and the recognizers) produces.
///
/// Raise it with any change that can alter the facts of some input, then
/// regenerate the golden with `dart run tool/update_facts_golden.dart`.
/// `test/infrastructure/dart/facts_corpus_test.dart` fails until both are
/// done. It names the cache namespace, `facts-v<factsFormatVersion>`, so an
/// old entry is never read as a new one.
const int factsFormatVersion = 2;

/// The canonical JSON of [facts]: fixed member order, no whitespace,
/// identifiers sorted, positions only. The path is not stored; [decodeFacts]
/// attaches the requested one, so one blob at two paths shares one entry.
String encodeFacts(DartFileFacts facts) => jsonEncode({
  'v': factsFormatVersion,
  'isWellFormed': facts.isWellFormed,
  'directives': [
    for (final directive in facts.directives)
      {
        'kind': directive.kind.name,
        'uri': directive.uri,
        ..._range(directive.location),
      },
  ],
  'annotatedDeclarations': [
    for (final declaration in facts.annotatedDeclarations)
      {
        'name': declaration.name,
        'annotations': declaration.annotations,
        'tokenHash': declaration.tokenHash,
        ..._range(declaration.location),
      },
  ],
  'testCalls': [
    for (final call in facts.testCalls)
      {
        'function': call.function,
        'description': call.description,
        'groups': call.groups,
        ..._range(call.location),
        'solo': call.solo == null ? null : _range(call.solo!),
        'skip': call.skip == null ? null : _range(call.skip!),
      },
  ],
  'identifiers': [...facts.identifiers]..sort(),
});

Map<String, Object?> _range(Location location) => {
  'start': [location.start.line, location.start.column],
  'end': [location.end.line, location.end.column],
};

/// The facts [text] encodes, with [path] in every location, or null when
/// [text] is not a document of this version or is damaged in any way.
///
/// It never throws: the cache is an optimization, and an entry it cannot
/// read is recomputed.
DartFileFacts? decodeFacts(String text, RepoPath path) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?> || json['v'] != factsFormatVersion) {
    return null;
  }
  final isWellFormed = json['isWellFormed'];
  final directives = _list(json['directives'], (o) => _directive(o, path));
  final declarations = _list(
    json['annotatedDeclarations'],
    (o) => _declaration(o, path),
  );
  final calls = _list(json['testCalls'], (o) => _testCall(o, path));
  final identifiers = _strings(json['identifiers']);
  if (isWellFormed is! bool ||
      directives == null ||
      declarations == null ||
      calls == null ||
      identifiers == null) {
    return null;
  }
  return DartFileFacts(
    directives: directives,
    annotatedDeclarations: declarations,
    testCalls: calls,
    identifiers: identifiers.toSet(),
    isWellFormed: isWellFormed,
  );
}

/// The elements of [value] through [convert], or null when [value] is not a
/// list or an element does not convert.
List<T>? _list<T>(Object? value, T? Function(Object?) convert) {
  if (value is! List<Object?>) return null;
  final result = <T>[];
  for (final element in value) {
    final converted = convert(element);
    if (converted == null) return null;
    result.add(converted);
  }
  return result;
}

List<String>? _strings(Object? value) =>
    _list(value, (o) => o is String ? o : null);

Directive? _directive(Object? json, RepoPath path) {
  if (json is! Map<String, Object?>) return null;
  final kind = DirectiveKind.values.asNameMap()[json['kind']];
  final uri = json['uri'];
  final location = _location(json, path);
  if (kind == null || uri is! String || location == null) return null;
  return Directive(kind: kind, uri: uri, location: location);
}

AnnotatedDeclaration? _declaration(Object? json, RepoPath path) {
  if (json is! Map<String, Object?>) return null;
  final name = json['name'];
  final annotations = _strings(json['annotations']);
  final tokenHash = json['tokenHash'];
  final location = _location(json, path);
  if (name is! String ||
      annotations == null ||
      tokenHash is! String ||
      location == null) {
    return null;
  }
  return AnnotatedDeclaration(
    name: name,
    annotations: annotations,
    tokenHash: tokenHash,
    location: location,
  );
}

TestCall? _testCall(Object? json, RepoPath path) {
  if (json is! Map<String, Object?>) return null;
  final function = json['function'];
  final description = json['description'];
  final groups = _strings(json['groups']);
  final location = _location(json, path);
  final solo = json['solo'];
  final skip = json['skip'];
  final soloLocation = solo == null ? null : _location(solo, path);
  final skipLocation = skip == null ? null : _location(skip, path);
  if (function is! String ||
      description is! String ||
      groups == null ||
      location == null ||
      (solo != null && soloLocation == null) ||
      (skip != null && skipLocation == null)) {
    return null;
  }
  return TestCall(
    function: function,
    description: description,
    groups: groups,
    location: location,
    solo: soloLocation,
    skip: skipLocation,
  );
}

Location? _location(Object? json, RepoPath path) {
  if (json is! Map<String, Object?>) return null;
  final start = _position(json['start']);
  final end = _position(json['end']);
  if (start == null || end == null) return null;
  return Location(path, start, end);
}

Position? _position(Object? json) {
  if (json is! List<Object?> || json.length != 2) return null;
  final [line, column] = json;
  if (line is! int || column is! int || line < 1 || column < 1) return null;
  return Position(line, column);
}

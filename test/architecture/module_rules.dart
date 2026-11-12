/// Import rules between the modules under `lib/src`, encoded once as data.
///
/// This is the executable form of the table in `docs/architecture.md`,
/// section 2 (ADR-0012). Change that table and this file together.
library;

import 'package:path/path.dart' as p;

/// URI prefix shared by every library under `lib/src`.
const _ownPrefix = 'package:stagelatch/src/';

/// `dart:` libraries that perform no I/O and read no global state.
const _pureDartLibraries = {
  'dart:core',
  'dart:async',
  'dart:convert',
  'dart:typed_data',
};

/// Packages the domain itself may use.
const _domainPackages = {'meta', 'collection'};

/// What one module under `lib/src` is allowed to import.
final class ModuleRule {
  /// Creates a rule. A null set means "anything".
  const new({required this.modules, this.dartLibraries, this.packages});

  /// Modules of this package that may be imported.
  final Set<String> modules;

  /// Allowed `dart:` libraries, or null when all are allowed.
  final Set<String>? dartLibraries;

  /// Allowed third-party packages, or null when all are allowed.
  final Set<String>? packages;
}

/// The module table. `root` stands for files directly under `lib/src`.
const moduleRules = <String, ModuleRule>{
  'root': ModuleRule(modules: {}, dartLibraries: {'dart:core'}, packages: {}),
  'domain': ModuleRule(
    modules: {'domain'},
    dartLibraries: _pureDartLibraries,
    packages: _domainPackages,
  ),
  'checks': ModuleRule(
    modules: {'domain', 'checks'},
    dartLibraries: _pureDartLibraries,
    packages: {..._domainPackages, 'pub_semver'},
  ),
  'application': ModuleRule(
    modules: {'domain', 'checks', 'application'},
    dartLibraries: _pureDartLibraries,
    packages: {..._domainPackages, 'glob', 'path', 'pub_semver', 'crypto'},
  ),
  'infrastructure': ModuleRule(
    modules: {'domain', 'application', 'infrastructure'},
  ),
  'cli': ModuleRule(
    modules: {
      'root',
      'domain',
      'checks',
      'application',
      'infrastructure',
      'cli',
    },
  ),
};

/// Returns the subset of [imports] that [module] is not allowed to import,
/// in the order given.
///
/// [imports] must already be normalized with [normalizeUri]: a relative URI
/// is always reported, because its target module cannot be known.
///
/// Throws [ArgumentError] when [module] is not in [moduleRules]. A new
/// top-level directory under `lib/src` must be added to the table first.
List<String> forbiddenImports({
  required String module,
  required Iterable<String> imports,
}) {
  final rule = moduleRules[module];
  if (rule == null) {
    throw ArgumentError.value(module, 'module', 'Not in the module table');
  }
  return [
    for (final uri in imports)
      if (!_isAllowed(rule, uri)) uri,
  ];
}

bool _isAllowed(ModuleRule rule, String uri) {
  if (uri.startsWith('dart:')) {
    return rule.dartLibraries?.contains(uri) ?? true;
  }
  if (uri.startsWith(_ownPrefix)) {
    return rule.modules.contains(_moduleOf(uri.substring(_ownPrefix.length)));
  }
  if (uri.startsWith('package:stagelatch/')) {
    // The public barrel re-exports from lib/src; importing it from inside
    // would create a cycle and hide which module is really used.
    return false;
  }
  if (uri.startsWith('package:')) {
    final name = uri.substring('package:'.length).split('/').first;
    return rule.packages?.contains(name) ?? true;
  }
  return false;
}

/// Returns the module of [path], a file path starting with `lib/src/` and
/// using forward slashes.
String moduleOfFile(String path) {
  const prefix = 'lib/src/';
  if (!path.startsWith(prefix)) {
    throw ArgumentError.value(path, 'path', 'Not under lib/src');
  }
  return _moduleOf(path.substring(prefix.length));
}

/// [relative] is a path below `lib/src`: its first directory is the module,
/// and a bare file name belongs to `root`.
String _moduleOf(String relative) {
  final slash = relative.indexOf('/');
  return slash < 0 ? 'root' : relative.substring(0, slash);
}

/// An `import`, `export` or `part` directive, up to its semicolon. Anchored
/// at the start of a line so that commented-out directives do not match.
final _directive = RegExp(
  r'^[ \t]*(?:import|export|part)\s+([^;]*);',
  multiLine: true,
);

/// A quoted string inside a directive: its URI, or one conditional branch.
final _quoted = RegExp('[\'"]([^\'"]+)[\'"]');

/// Returns every URI named by the directives of [source], in source order.
///
/// Conditional imports contribute one URI per branch.
List<String> directiveUris(String source) => [
  for (final directive in _directive.allMatches(source))
    for (final uri in _quoted.allMatches(directive.group(1) ?? ''))
      uri.group(1) ?? '',
];

/// Turns a relative [uri] found in [importer] into a `package:` URI.
///
/// [importer] is a path starting with `lib/` and using forward slashes.
/// `dart:` and `package:` URIs are returned unchanged.
String normalizeUri(String uri, {required String importer}) {
  if (uri.contains(':')) return uri;
  final resolved = p.posix.normalize(
    p.posix.join(p.posix.dirname(importer), uri),
  );
  const lib = 'lib/';
  return resolved.startsWith(lib)
      ? 'package:stagelatch/${resolved.substring(lib.length)}'
      : resolved;
}

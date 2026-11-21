/// Resolves a bare executable name to an absolute path via PATH.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Walks [pathEntries] and returns the first absolute path to [name].
///
/// Skips empty entries, `.`, relative directories, and any directory whose
/// real path is [repoRoot] or inside it. That keeps Windows CreateProcessW
/// from picking a planted executable in the working directory or a
/// repository-controlled PATH entry when [Process.start] is given a bare
/// name (security: repository content is hostile).
///
/// When [name] already contains a directory separator it is returned as-is:
/// the caller supplied an explicit path.
///
/// [fileExists] and [realPath] default to the local file system; tests
/// replace them. [pathExtensions] is Windows PATHEXT (including a leading
/// empty string so the bare name is tried first).
String? resolvePathExecutable({
  required String name,
  required Iterable<String> pathEntries,
  String? repoRoot,
  bool isWindows = false,
  List<String> pathExtensions = const [''],
  bool Function(String path)? fileExists,
  String? Function(String path)? realPath,
  p.Context? context,
}) {
  final ctx = context ?? p.context;
  final exists = fileExists ?? FileSystemEntity.isFileSync;
  final resolve = realPath ?? _defaultRealPath;

  if (_hasSeparator(name, ctx)) return name;

  final realRepo = repoRoot == null ? null : resolve(repoRoot);
  final extensions = isWindows && pathExtensions.isNotEmpty
      ? pathExtensions
      : const [''];

  for (final entry in pathEntries) {
    if (!_isUsablePathEntry(
      entry,
      ctx: ctx,
      resolve: resolve,
      realRepo: realRepo,
    )) {
      continue;
    }
    final directory = resolve(entry);
    if (directory == null) continue;
    for (final extension in extensions) {
      final candidate = ctx.join(directory, '$name$extension');
      if (exists(candidate)) return candidate;
    }
  }
  return null;
}

/// Whether [name] already names a path rather than a bare executable.
bool _hasSeparator(String name, p.Context ctx) {
  if (name.contains('/')) return true;
  if (ctx.style == p.Style.windows && name.contains(r'\')) return true;
  return false;
}

bool _isUsablePathEntry(
  String entry, {
  required p.Context ctx,
  required String? Function(String path) resolve,
  required String? realRepo,
}) {
  if (entry.isEmpty || entry == '.') return false;
  if (!ctx.isAbsolute(entry)) return false;
  final real = resolve(entry);
  if (real == null) return false;
  if (realRepo == null) return true;
  return !ctx.equals(real, realRepo) && !ctx.isWithin(realRepo, real);
}

String? _defaultRealPath(String path) {
  try {
    if (Directory(path).existsSync()) {
      return Directory(path).resolveSymbolicLinksSync();
    }
    if (File(path).existsSync()) {
      return File(path).resolveSymbolicLinksSync();
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

/// Splits a PATH value with the platform separator.
List<String> splitPathEnv(String pathEnv, {required bool isWindows}) =>
    pathEnv.split(isWindows ? ';' : ':');

/// PATHEXT entries for Windows, always including a leading empty string so
/// the bare name is tried before the suffixes.
List<String> pathExtSuffixes(String? pathExt) {
  final raw = pathExt ?? '';
  final suffixes = <String>{''};
  for (final part in raw.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    suffixes.add(trimmed.startsWith('.') ? trimmed : '.$trimmed');
  }
  return List.unmodifiable(suffixes);
}

/// Locates the SDK on the file system (docs/specs/dart-toolchain.md,
/// section 1).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';

/// Tries `sdk_path`, then FVM, then `PATH`; the first match wins.
///
/// Every candidate is checked after resolving symbolic links: the SDK must
/// be outside the repository, because `sdk_path` and `.fvm/` are
/// repository content and could point at a committed binary (security S2).
final class FileSdkLocator implements SdkLocator {
  /// Creates a locator for the repository at `repoRoot`.
  new({required this._repoRoot, required this._environment});

  final String _repoRoot;
  final Environment _environment;

  static final bool _windows = Platform.isWindows;

  @override
  Future<ResolvedSdk> locate(Config config) async {
    final sdkPath = config.sdkPath;
    if (sdkPath != null) {
      final dir = p.normalize(p.join(_repoRoot, sdkPath));
      return await _shaped(dir, SdkSource.sdkPath) ??
          (throw ConfigException(
            'sdk_path "$sdkPath" is not a Dart or Flutter SDK.',
          ));
    }

    final fvmLink = p.join(_repoRoot, '.fvm', 'flutter_sdk');
    final fvmLinkType = FileSystemEntity.typeSync(fvmLink, followLinks: false);
    if (fvmLinkType != FileSystemEntityType.notFound) {
      return await _shaped(fvmLink, SdkSource.fvm) ??
          (throw const ConfigException(
            '.fvm/flutter_sdk is not a Dart or Flutter SDK.',
          ));
    }
    final fvmrc = File(p.join(_repoRoot, '.fvmrc'));
    if (fvmrc.existsSync()) {
      final version = _fvmVersion(await fvmrc.readAsString());
      final dir = p.join(_fvmCache(), 'versions', version);
      return await _shaped(dir, SdkSource.fvm) ??
          (throw ConfigException(
            '.fvmrc requests Flutter $version, which is not installed at '
            '$dir.',
          ));
    }

    // On Windows a Dart SDK has bin\dart.exe, but a Flutter SDK puts only
    // bin\dart.bat on PATH.
    final names = _windows ? const ['dart.exe', 'dart.bat'] : const ['dart'];
    for (final entry in _pathEntries()) {
      for (final name in names) {
        final executable = File(p.join(entry, name));
        if (!executable.existsSync()) continue;
        final real = await executable.resolveSymbolicLinks();
        for (String? dir = p.dirname(real); dir != null; dir = _up(dir)) {
          final sdk = await _shaped(dir, SdkSource.path);
          if (sdk != null) return sdk;
        }
      }
    }
    throw const ConfigException(
      'No Dart SDK found. Install Dart or set sdk_path.',
    );
  }

  /// The SDK rooted at [dir], or null when [dir] has neither shape.
  ///
  /// Throws when the real directory is inside the repository.
  Future<ResolvedSdk?> _shaped(String dir, SdkSource source) async {
    if (!Directory(dir).existsSync()) return null;
    final real = await Directory(dir).resolveSymbolicLinks();
    final flutterDart = p.join(real, 'bin', 'cache', 'dart-sdk');
    final String dartRoot;
    final String? flutter;
    if (File(p.join(flutterDart, 'version')).existsSync()) {
      dartRoot = flutterDart;
      flutter = p.join(real, 'bin', _windows ? 'flutter.bat' : 'flutter');
    } else if (File(p.join(real, 'version')).existsSync() &&
        File(_dartIn(real)).existsSync()) {
      dartRoot = real;
      flutter = null;
    } else {
      return null;
    }
    final repo = await Directory(_repoRoot).resolveSymbolicLinks();
    if (p.equals(real, repo) || p.isWithin(repo, real)) {
      throw ConfigException(
        'The Dart SDK must be outside the repository: $real.',
      );
    }
    final version = (await File(p.join(dartRoot, 'version')).readAsString())
        .trim()
        .split(RegExp(r'\s+')) // linear: a single character class
        .first;
    return ResolvedSdk(
      root: dartRoot,
      dartExecutable: _dartIn(dartRoot),
      flutterExecutable: flutter,
      version: version,
      source: source,
    );
  }

  String _dartIn(String root) =>
      p.join(root, 'bin', _windows ? 'dart.exe' : 'dart');

  String _fvmVersion(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const ConfigException('.fvmrc is not valid JSON.');
    }
    if (decoded case {'flutter': final String version}
        when version.isNotEmpty) {
      return version;
    }
    throw const ConfigException('.fvmrc does not name a Flutter version.');
  }

  String _fvmCache() {
    final variables = _environment.variables;
    final configured = variables['FVM_CACHE_PATH'];
    if (configured != null && configured.isNotEmpty) return configured;
    final home = variables['HOME'] ?? variables['USERPROFILE'] ?? '';
    return p.join(home, 'fvm');
  }

  Iterable<String> _pathEntries() => (_environment.variables['PATH'] ?? '')
      .split(_windows ? ';' : ':')
      .where((entry) => entry.isNotEmpty);

  static String? _up(String dir) {
    final parent = p.dirname(dir);
    return parent == dir ? null : parent;
  }
}

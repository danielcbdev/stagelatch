/// Formatter settings the way `dart format` derives them from disk.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch_bench/probe.dart';
import 'package:yaml/yaml.dart';

typedef _Package = ({String name, String root, String? languageVersion});

/// Page width, trailing-comma mode and language version for one file.
final class FormatOptions {
  /// Creates options.
  const new({
    required this.languageVersion,
    this.pageWidth,
    this.preserveTrailingCommas = false,
  });

  /// Resolves the options of [path] as `dart format` does: the nearest
  /// `analysis_options.yaml` (following `include:`), and the language
  /// version of the package in the nearest `package_config.json`. Files are
  /// read through [input]'s overlays, so snapshot content wins.
  factory resolve(ProbeInput input, String path) {
    final config = _nearest(p.dirname(path), '.dart_tool/package_config.json');
    final packages = config == null ? const <_Package>[] : _packages(config);
    String? version;
    var depth = -1;
    for (final package in packages) {
      if (p.isWithin(package.root, path) && package.root.length > depth) {
        depth = package.root.length;
        version = package.languageVersion;
      }
    }
    final options = _nearest(p.dirname(path), 'analysis_options.yaml');
    final formatter = options == null
        ? null
        : _formatterSection(input, options, packages, {});
    return FormatOptions(
      languageVersion: version == null
          ? Version(3, 13, 0)
          : Version.parse('$version.0'),
      pageWidth: switch (formatter?['page_width']) {
        final int width => width,
        _ => null,
      },
      preserveTrailingCommas: formatter?['trailing_commas'] == 'preserve',
    );
  }

  /// Language version of the package that contains the file.
  final Version languageVersion;

  /// `formatter: page_width` of the nearest `analysis_options.yaml`.
  final int? pageWidth;

  /// Whether `formatter: trailing_commas` is `preserve`.
  final bool preserveTrailingCommas;

  static String? _nearest(String dir, String relative) {
    var current = dir;
    while (true) {
      final candidate = p.join(current, relative);
      if (File(candidate).existsSync()) return candidate;
      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }

  static List<_Package> _packages(String configPath) {
    final json = jsonDecode(File(configPath).readAsStringSync());
    final base = Uri.file(configPath);
    if (json case {'packages': final List<Object?> list}) {
      return [
        for (final entry in list)
          if (entry case {
            'name': final String name,
            'rootUri': final String rootUri,
          })
            (
              name: name,
              root: p.normalize(base.resolve(rootUri).toFilePath()),
              languageVersion: switch (entry) {
                {'languageVersion': final String v} => v,
                _ => null,
              },
            ),
      ];
    }
    return const [];
  }

  static Map<Object?, Object?>? _formatterSection(
    ProbeInput input,
    String file,
    List<_Package> packages,
    Set<String> seen,
  ) {
    if (!seen.add(file)) return null;
    final text =
        input.overlays[file] ??
        (File(file).existsSync() ? File(file).readAsStringSync() : null);
    if (text == null) return null;
    final yaml = loadYaml(text);
    if (yaml is! Map) return null;
    if (yaml['formatter'] case final Map<Object?, Object?> section) {
      return section;
    }
    final include = yaml['include'];
    final includes = switch (include) {
      final String one => [one],
      final List<Object?> many => [...many.whereType<String>()],
      _ => const <String>[],
    };
    // Later includes override earlier ones, so search from the end.
    for (final uri in includes.reversed) {
      final target = _resolveInclude(file, uri, packages);
      if (target == null) continue;
      final section = _formatterSection(input, target, packages, seen);
      if (section != null) return section;
    }
    return null;
  }

  static String? _resolveInclude(
    String from,
    String uri,
    List<_Package> packages,
  ) {
    if (!uri.startsWith('package:')) {
      return p.normalize(p.join(p.dirname(from), uri));
    }
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    final name = rest.substring(0, slash);
    for (final package in packages) {
      if (package.name == name) {
        return p.join(package.root, 'lib', rest.substring(slash + 1));
      }
    }
    return null;
  }
}

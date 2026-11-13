/// Loading and validating `stagelatch.yaml` (docs/specs/config.md).
library;

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/check_catalog.dart';
import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/config/default_hooks.dart';
import 'package:stagelatch/src/application/config/hook_selector.dart';
import 'package:stagelatch/src/application/config/settings.dart';
import 'package:stagelatch/src/application/config/value_parsers.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/working_tree.dart';
import 'package:stagelatch/src/domain/dart/dart_toolchain.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// The name of the configuration file, at the repository root.
const String configFileName = 'stagelatch.yaml';

/// The notice reported when the config exists only in the working tree.
const String configNotStagedNotice =
    'stagelatch.yaml is not staged; using the working tree copy.';

/// A loaded configuration and what the user should be told about it.
final class LoadedConfig {
  /// Creates the result.
  const new({required this.config, this.notices = const []});

  /// The validated configuration.
  final Config config;

  /// Sentences to show with the report, such as [configNotStagedNotice].
  final List<String> notices;
}

/// Reads `stagelatch.yaml` and turns it into a [Config].
final class ConfigLoader {
  /// Creates a loader.
  const new(this._documents, this._worktree);

  final Documents _documents;
  final WorkingTree _worktree;

  /// Loads the configuration that applies to [snapshot].
  ///
  /// The file is read from the snapshot being judged, so that an unstaged
  /// edit cannot change the verdict (ADR-0015). When the snapshot has no
  /// config but the working tree does, that copy is used and a notice says
  /// so. When there is none at all, every default applies.
  ///
  /// The whole file is validated before anything runs. Throws
  /// [ConfigException] for the first problem in document order, except
  /// that `min_version` is checked before everything else: a tool that is
  /// too old should say so instead of complaining about what it does not
  /// know yet.
  Future<LoadedConfig> load(
    SnapshotFiles snapshot, {
    required Version toolVersion,
    required CheckCatalog catalog,
  }) async {
    final path = RepoPath(configFileName);
    final notices = <String>[];
    var document = await _documents.yaml(snapshot, path);
    if (document is DocumentMissing) {
      final text = await _worktree.readText(path);
      if (text != null) {
        document = _documents.parseYaml(text, path);
        notices.add(configNotStagedNotice);
      }
    }
    final parser = _ConfigParser(catalog: catalog, toolVersion: toolVersion);
    final config = switch (document) {
      DocumentMissing() => parser.build(),
      DocumentInvalid(:final location, :final reason) => throw ConfigException(
        '${_sentence(reason)}.',
        location: location,
      ),
      DocumentParsed(:final root) => parser.parse(root),
    };
    return LoadedConfig(config: config, notices: List.unmodifiable(notices));
  }
}

/// A Dart identifier. One character class under one quantifier, so
/// matching is linear (security rule S6).
final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

/// Reads one settings value, already known to be under an allowed key.
typedef _Reader = void Function(LocatedNode value, String key);

/// Walks a parsed config and accumulates a [Config], starting from the
/// defaults. One instance parses one file.
final class _ConfigParser {
  new({required this.catalog, required this.toolVersion});

  final CheckCatalog catalog;
  final Version toolVersion;

  Version? _minVersion;
  final Map<String, List<HookSelector>> _hooks = {};
  final Map<RuleId, RuleLevel> _rules = {};
  List<Glob> _exclude = const [];
  String? _sdkPath;
  Duration _timeBudget = const Duration(seconds: 2);
  RepoPath _baselinePath = RepoPath('.stagelatch/baseline.json');
  FormatSettings _format = const FormatSettings();
  AnalyzeSettings _analyze = const AnalyzeSettings();
  CodegenSettings _codegen = const CodegenSettings();
  PubspecSettings _pubspec = const PubspecSettings();
  AssetsSettings _assets = AssetsSettings();
  TestsSettings _tests = const TestsSettings();

  /// Validates [root] and returns the resulting configuration.
  Config parse(LocatedNode root) {
    // An empty file parses to a null scalar and means "all defaults".
    if (root case LocatedScalar(value: null)) return build();
    if (root is! LocatedMap) {
      _fail(
        'Expected a map at the top level.',
        Location.wholeFile(root.location.path),
      );
    }
    if (root.entries['min_version'] case final entry?) _readMinVersion(entry);
    for (final MapEntry(:key, value: entry) in root.entries.entries) {
      switch (key) {
        case 'min_version':
          break; // Read first, above.
        case 'hooks':
          _readHooks(entry);
        case 'rules':
          _readRules(entry);
        case 'exclude':
          _exclude = _globs(entry.value, key);
        case 'sdk_path':
          _sdkPath = _string(entry.value, key);
        case 'time_budget':
          _timeBudget = _parsed('duration', entry.value, key, parseDuration);
        case 'baseline':
          _baselinePath = _parsed('path', entry.value, key, RepoPath.new);
        case 'format':
          _readFormat(entry);
        case 'analyze':
          _readAnalyze(entry);
        case 'codegen':
          _readCodegen(entry);
        case 'pubspec':
          _readPubspec(entry);
        case 'assets':
          _readAssets(entry);
        case 'tests':
          _readTests(entry);
        case 'custom_checks':
          _fail(
            'custom_checks requires stagelatch >= 1.0.0.',
            entry.keyLocation,
          );
        default:
          _fail('Unknown key "$key" at the top level.', entry.keyLocation);
      }
    }
    return build();
  }

  /// The configuration read so far, with defaults for everything else.
  Config build() {
    final preCommit =
        _hooks[preCommitHook] ?? defaultHookSelectors(preCommitHook, catalog);
    final prePush =
        _hooks[prePushHook] ?? defaultHookSelectors(prePushHook, catalog);
    return Config(
      minVersion: _minVersion,
      hooks: Map.unmodifiable({
        preCommitHook: preCommit,
        prePushHook: prePush,
        ciHook: _hooks[ciHook] ?? unionOfSelectors(preCommit, prePush),
      }),
      rules: Map.unmodifiable(_rules),
      exclude: _exclude,
      sdkPath: _sdkPath,
      timeBudget: _timeBudget,
      baselinePath: _baselinePath,
      format: _format,
      analyze: _analyze,
      codegen: _codegen,
      pubspec: _pubspec,
      assets: _assets,
      tests: _tests,
    );
  }

  void _readMinVersion(LocatedEntry entry) {
    final required = _parsed(
      'version',
      entry.value,
      'min_version',
      Version.parse,
    );
    if (toolVersion < required) {
      _fail(
        'This repository requires stagelatch >= $required; '
        'you have $toolVersion. '
        'Run: dart pub global activate stagelatch',
        entry.value.location,
      );
    }
    _minVersion = required;
  }

  void _readHooks(LocatedEntry entry) {
    final hooks = _mapOf(entry.value, 'hooks');
    for (final MapEntry(key: hook, value: child) in hooks.entries) {
      if (!hookNames.contains(hook)) {
        _fail(
          'Unknown hook "$hook". Expected pre-commit, pre-push or ci.',
          child.keyLocation,
        );
      }
      // A hook left without a value keeps its default list.
      if (child.value case LocatedScalar(value: null)) continue;
      _hooks[hook] = List.unmodifiable([
        for (final item in _strings(child.value, 'hooks.$hook'))
          _selector(item.text, hook, item.location),
      ]);
    }
  }

  HookSelector _selector(String text, String hook, Location location) {
    final HookSelector selector;
    try {
      selector = HookSelector.parse(text);
    } on FormatException {
      _fail('Invalid selector "$text" in "hooks.$hook".', location);
    }
    if (!catalog.checkIds.contains(selector.check)) {
      _fail('Unknown check "${selector.check}" in hooks.$hook.', location);
    }
    final rule = selector.ruleId;
    if (rule != null && !_knowsRule(rule)) {
      _fail('Unknown rule "$rule".', location);
    }
    return selector;
  }

  void _readRules(LocatedEntry entry) {
    final rules = _mapOf(entry.value, 'rules');
    for (final MapEntry(:key, value: child) in rules.entries) {
      final RuleId id;
      try {
        id = RuleId.parse(key);
      } on FormatException {
        _fail('Unknown rule "$key".', child.keyLocation);
      }
      if (!_knowsRule(id)) _fail('Unknown rule "$id".', child.keyLocation);
      _rules[id] = switch (child.value) {
        LocatedScalar(value: 'error') => RuleLevel.error,
        LocatedScalar(value: 'warning') => RuleLevel.warning,
        // A YAML 1.1 parser reads a bare `off` as the boolean false.
        LocatedScalar(value: 'off' || false) => RuleLevel.off,
        _ => _fail(
          'Level of "$id" must be error, warning or off.',
          child.value.location,
        ),
      };
    }
  }

  /// Whether [rule] is declared by a check, or belongs to a check whose
  /// rule names are open-ended.
  bool _knowsRule(RuleId rule) =>
      catalog.hasRule(rule) ||
      (catalog.checkIds.contains(rule.check) &&
          catalog.hasDynamicRules(rule.check));

  void _readFormat(LocatedEntry entry) {
    var fix = _format.fix;
    _section(entry, 'format', {'fix': (node, key) => fix = _bool(node, key)});
    _format = FormatSettings(fix: fix);
  }

  void _readAnalyze(LocatedEntry entry) {
    var scope = _analyze.scope;
    var failOn = _analyze.failOn;
    _section(entry, 'analyze', {
      'scope': (node, key) => scope = _parsed(
        'scope',
        node,
        key,
        (text) => _named(AnalyzeScope.values, text),
      ),
      'fail_on': (node, key) => failOn = {
        for (final item in _strings(node, key))
          _parsedText(
            'severity',
            item.text,
            key,
            item.location,
            (text) => _named(DiagnosticSeverity.values, text),
          ),
      },
    });
    _analyze = AnalyzeSettings(scope: scope, failOn: Set.unmodifiable(failOn));
  }

  void _readCodegen(LocatedEntry entry) {
    var committed = _codegen.generatedFilesCommitted;
    var suffixes = _codegen.generatedSuffixes;
    _section(entry, 'codegen', {
      'generated_files_committed': (node, key) => committed = _bool(node, key),
      'generated_suffixes': (node, key) => suffixes = List.unmodifiable([
        for (final item in _strings(node, key)) item.text,
      ]),
    });
    _codegen = CodegenSettings(
      generatedFilesCommitted: committed,
      generatedSuffixes: suffixes,
    );
  }

  void _readPubspec(LocatedEntry entry) {
    var branches = _pubspec.monotonicBuildNumber;
    var requireSha = _pubspec.requireSha;
    _section(entry, 'pubspec', {
      'monotonic_build_number': (node, key) => branches = _globs(node, key),
      'require_sha': (node, key) => requireSha = _bool(node, key),
    });
    _pubspec = PubspecSettings(
      monotonicBuildNumber: branches,
      requireSha: requireSha,
    );
  }

  void _readAssets(LocatedEntry entry) {
    var maxFileSize = _assets.maxFileSize;
    var roots = _assets.roots;
    var ignore = _assets.ignore;
    _section(entry, 'assets', {
      'max_file_size': (node, key) =>
          maxFileSize = _parsed('size', node, key, parseSize),
      'roots': (node, key) => roots = List.unmodifiable([
        for (final item in _strings(node, key))
          _parsedText('directory', item.text, key, item.location, _directory),
      ]),
      'ignore': (node, key) => ignore = _globs(node, key),
    });
    _assets = AssetsSettings(
      maxFileSize: maxFileSize,
      roots: roots,
      ignore: ignore,
    );
  }

  void _readTests(LocatedEntry entry) {
    var functions = _tests.functions;
    _section(entry, 'tests', {
      'functions': (node, key) => functions = List.unmodifiable([
        for (final item in _strings(node, key))
          _parsedText(
            'identifier',
            item.text,
            key,
            item.location,
            _identifierOf,
          ),
      ]),
    });
    _tests = TestsSettings(functions: functions);
  }

  /// Reads the keys of a settings section, rejecting any key that has no
  /// reader. The allowed keys of a section are exactly the keys of
  /// [readers], so validation and reading cannot drift apart.
  void _section(LocatedEntry entry, String name, Map<String, _Reader> readers) {
    final section = _mapOf(entry.value, name);
    for (final MapEntry(:key, value: child) in section.entries) {
      final reader = readers[key];
      if (reader == null) {
        _fail('Unknown key "$key" under "$name".', child.keyLocation);
      }
      reader(child.value, '$name.$key');
    }
  }

  List<Glob> _globs(LocatedNode node, String key) => List.unmodifiable([
    for (final item in _strings(node, key))
      _parsedText('glob', item.text, key, item.location, _glob),
  ]);

  /// Globs are matched against repository paths, which always use `/` and
  /// are case-sensitive, so the POSIX rules apply on every platform.
  static Glob _glob(String pattern) =>
      Glob(pattern, context: p.posix, caseSensitive: true);

  /// A directory of the repository; one trailing `/` is allowed.
  static RepoPath _directory(String text) =>
      RepoPath(text.endsWith('/') ? text.substring(0, text.length - 1) : text);

  static String _identifierOf(String text) => _identifier.hasMatch(text)
      ? text
      : throw FormatException('Not an identifier.', text);

  /// The value of [values] whose name is [text].
  static T _named<T extends Enum>(List<T> values, String text) =>
      values.firstWhere(
        (value) => value.name == text,
        orElse: () => throw FormatException('Not one of the values.', text),
      );

  /// Parses the scalar at [node] with [parse], reporting a
  /// [FormatException] as `Invalid <kind> "<text>" in "<key>".`
  ///
  /// A number is accepted as its text, so that `max_file_size: 500` is
  /// reported as an invalid size and not as a type error.
  T _parsed<T>(
    String kind,
    LocatedNode node,
    String key,
    T Function(String text) parse,
  ) {
    final text = switch (node) {
      LocatedScalar(value: final String text) => text,
      LocatedScalar(value: final num number) => number.toString(),
      _ => _fail(
        '"$key" must be a string, found ${_describe(node)}.',
        node.location,
      ),
    };
    return _parsedText(kind, text, key, node.location, parse);
  }

  T _parsedText<T>(
    String kind,
    String text,
    String key,
    Location location,
    T Function(String text) parse,
  ) {
    try {
      return parse(text);
    } on FormatException {
      _fail('Invalid $kind "$text" in "$key".', location);
    }
  }

  String _string(LocatedNode node, String key) => switch (node) {
    LocatedScalar(value: final String text) => text,
    _ => _fail(
      '"$key" must be a string, found ${_describe(node)}.',
      node.location,
    ),
  };

  bool _bool(LocatedNode node, String key) => switch (node) {
    LocatedScalar(value: final bool flag) => flag,
    _ => _fail(
      '"$key" must be a boolean, found ${_describe(node)}.',
      node.location,
    ),
  };

  /// The entries of a map. A key without a value is an empty map, so that
  /// a section can be left empty.
  Map<String, LocatedEntry> _mapOf(LocatedNode node, String key) =>
      switch (node) {
        LocatedMap(:final entries) => entries,
        LocatedScalar(value: null) => const {},
        _ => _fail(
          '"$key" must be a map, found ${_describe(node)}.',
          node.location,
        ),
      };

  /// The items of a list of strings, each with where it is written. A key
  /// without a value is an empty list.
  List<({String text, Location location})> _strings(
    LocatedNode node,
    String key,
  ) {
    final items = switch (node) {
      LocatedList(:final items) => items,
      LocatedScalar(value: null) => const <LocatedNode>[],
      _ => _fail(
        '"$key" must be a list, found ${_describe(node)}.',
        node.location,
      ),
    };
    return [
      for (final item in items)
        switch (item) {
          LocatedScalar(value: final String text) => (
            text: text,
            location: item.location,
          ),
          _ => _fail(
            '"$key" must be a list of strings, found ${_describe(item)}.',
            item.location,
          ),
        },
    ];
  }

  static String _describe(LocatedNode node) => switch (node) {
    LocatedMap() => 'a map',
    LocatedList() => 'a list',
    LocatedScalar(value: String()) => 'a string',
    LocatedScalar(value: bool()) => 'a boolean',
    LocatedScalar(value: num()) => 'a number',
    LocatedScalar() => 'null',
  };

  Never _fail(String message, Location location) =>
      throw ConfigException(message, location: location);
}

/// [reason] with its first letter in upper case, to start a sentence.
String _sentence(String reason) =>
    reason.isEmpty ? reason : reason[0].toUpperCase() + reason.substring(1);

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/config/config_loader.dart';
import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/pipeline/check_registry.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';
import 'package:stagelatch/src/infrastructure/dart/file_sdk_locator.dart';
import 'package:stagelatch/src/infrastructure/documents/structured_documents.dart';
import 'package:test/test.dart';

import '../../support/fake_snapshot_files.dart';
import '../../support/fake_working_tree.dart';

final String _exe = Platform.isWindows ? '.exe' : '';

void main() {
  late String temp;
  late String repo;
  late String outside;

  setUp(() async {
    final created = await Directory.systemTemp.createTemp('sdk_locator_');
    temp = await created.resolveSymbolicLinks();
    repo = p.join(temp, 'repo');
    outside = p.join(temp, 'outside');
    await Directory(repo).create();
    await Directory(outside).create();
  });

  tearDown(() => Directory(temp).delete(recursive: true));

  void write(String path, String content) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// A Dart SDK root at [dir].
  String dartSdk(String dir, {String version = '3.13.4'}) {
    write(p.join(dir, 'version'), '$version\n');
    write(p.join(dir, 'bin', 'dart$_exe'), '');
    return dir;
  }

  /// A Flutter SDK root at [dir], with its Dart SDK under bin/cache.
  String flutterSdk(String dir, {String version = '3.13.4'}) {
    dartSdk(p.join(dir, 'bin', 'cache', 'dart-sdk'), version: version);
    write(
      p.join(dir, 'bin', Platform.isWindows ? 'flutter.bat' : 'flutter'),
      '',
    );
    write(p.join(dir, 'bin', Platform.isWindows ? 'dart.bat' : 'dart'), '');
    return dir;
  }

  Future<Config> config([String yaml = 'hooks: {}\n']) async =>
      (await ConfigLoader(const StructuredDocuments(), FakeWorkingTree()).load(
        FakeSnapshotFiles({'stagelatch.yaml': yaml}),
        toolVersion: Version.parse('0.1.0'),
        catalog: CheckRegistry(const []),
      )).config;

  FileSdkLocator locator({
    List<String> path = const [],
    Map<String, String> more = const {},
  }) => FileSdkLocator(
    repoRoot: repo,
    environment: Environment(
      workingDirectory: repo,
      variables: {
        'PATH': path.join(Platform.isWindows ? ';' : ':'),
        'HOME': p.join(temp, 'home'),
        'USERPROFILE': p.join(temp, 'home'),
        ...more,
      },
      stdoutIsTerminal: false,
      stdinIsTerminal: false,
    ),
  );

  Future<ConfigException> failure(Future<ResolvedSdk> located) async {
    try {
      await located;
    } on ConfigException catch (error) {
      return error;
    }
    fail('Expected a ConfigException.');
  }

  test('sdk_path wins over FVM and PATH', () async {
    final sdk = dartSdk(p.join(outside, 'sdk'));
    flutterSdk(p.join(temp, 'home', 'fvm', 'versions', '3.29.0'));
    write(p.join(repo, '.fvmrc'), '{"flutter": "3.29.0"}');
    final onPath = dartSdk(p.join(outside, 'other'));

    final resolved = await locator(path: [p.join(onPath, 'bin')])
        .locate(await config('sdk_path: ../outside/sdk\n'));

    expect(resolved.source, SdkSource.sdkPath);
    expect(resolved.root, sdk);
    expect(resolved.dartExecutable, p.join(sdk, 'bin', 'dart$_exe'));
    expect(resolved.flutterExecutable, isNull);
  });

  test('a Flutter root resolves to bin/cache/dart-sdk and exposes '
      'flutter', () async {
    final flutter = flutterSdk(p.join(outside, 'flutter'));

    final resolved = await locator().locate(
      await config('sdk_path: ../outside/flutter\n'),
    );

    expect(resolved.root, p.join(flutter, 'bin', 'cache', 'dart-sdk'));
    expect(resolved.flutterExecutable, isNotNull);
    expect(resolved.version, '3.13.4');
  });

  test('the version is the first token of the version file', () async {
    dartSdk(p.join(outside, 'sdk'), version: '3.14.0-12.0.dev (beta)');

    final resolved = await locator().locate(
      await config('sdk_path: ../outside/sdk\n'),
    );

    expect(resolved.version, '3.14.0-12.0.dev');
  });

  test('.fvm/flutter_sdk is used when present', () async {
    final flutter = flutterSdk(p.join(outside, 'fvm_flutter'));
    await Link(p.join(repo, '.fvm', 'flutter_sdk'))
        .create(flutter, recursive: true);

    final resolved = await locator().locate(await config());

    expect(resolved.source, SdkSource.fvm);
    expect(resolved.root, p.join(flutter, 'bin', 'cache', 'dart-sdk'));
  }, testOn: '!windows');

  test('.fvmrc resolves under FVM_CACHE_PATH, else under the home '
      'directory', () async {
    write(p.join(repo, '.fvmrc'), '{"flutter": "3.29.0"}');
    final cached = flutterSdk(p.join(outside, 'cache', 'versions', '3.29.0'));
    final home = flutterSdk(p.join(temp, 'home', 'fvm', 'versions', '3.29.0'));

    final withCache = await locator(
      more: {'FVM_CACHE_PATH': p.join(outside, 'cache')},
    ).locate(await config());
    final withoutCache = await locator().locate(await config());

    expect(withCache.root, p.join(cached, 'bin', 'cache', 'dart-sdk'));
    expect(withoutCache.root, p.join(home, 'bin', 'cache', 'dart-sdk'));
    expect(withoutCache.source, SdkSource.fvm);
  });

  test('PATH is searched in order for dart', () async {
    final first = dartSdk(p.join(outside, 'first'));
    dartSdk(p.join(outside, 'second'));

    final resolved = await locator(
      path: [
        p.join(outside, 'missing'),
        p.join(first, 'bin'),
        p.join(outside, 'second', 'bin'),
      ],
    ).locate(await config());

    expect(resolved.source, SdkSource.path);
    expect(resolved.root, first);
  });

  test('a dart on PATH inside a Flutter checkout resolves to its Dart '
      'SDK', () async {
    final flutter = flutterSdk(p.join(outside, 'flutter'));

    final resolved = await locator(path: [p.join(flutter, 'bin')])
        .locate(await config());

    expect(resolved.root, p.join(flutter, 'bin', 'cache', 'dart-sdk'));
    expect(resolved.flutterExecutable, isNotNull);
  });

  test('a symlinked dart on PATH is followed to its SDK', () async {
    final sdk = dartSdk(p.join(outside, 'sdk'));
    await Link(p.join(outside, 'links', 'dart'))
        .create(p.join(sdk, 'bin', 'dart'), recursive: true);

    final resolved = await locator(path: [p.join(outside, 'links')])
        .locate(await config());

    expect(resolved.root, sdk);
  }, testOn: '!windows');

  test('an SDK inside the repository is rejected', () async {
    final inside = dartSdk(p.join(repo, 'tools', 'sdk'));

    final error = await failure(
      locator().locate(await config('sdk_path: tools/sdk\n')),
    );

    expect(
      error.message,
      'The Dart SDK must be outside the repository: $inside.',
    );
  });

  test('a symlink in the repository that points outside is accepted', () async {
    final flutter = flutterSdk(p.join(outside, 'flutter'));
    await Link(p.join(repo, '.fvm', 'flutter_sdk'))
        .create(flutter, recursive: true);

    final resolved = await locator().locate(await config());

    expect(resolved.root, p.join(flutter, 'bin', 'cache', 'dart-sdk'));
  }, testOn: '!windows');

  test('each unresolved source has its own message', () async {
    final e1 = await failure(
      locator().locate(await config('sdk_path: nope\n')),
    );
    write(p.join(repo, '.fvmrc'), '{"flutter": "9.9.9"}');
    final e2 = await failure(locator().locate(await config()));
    File(p.join(repo, '.fvmrc')).deleteSync();
    final e3 = await failure(locator().locate(await config()));

    expect(e1.message, 'sdk_path "nope" is not a Dart or Flutter SDK.');
    expect(
      e2.message,
      '.fvmrc requests Flutter 9.9.9, which is not installed at '
      '${p.join(temp, 'home', 'fvm', 'versions', '9.9.9')}.',
    );
    expect(e3.message, 'No Dart SDK found. Install Dart or set sdk_path.');
  });
}

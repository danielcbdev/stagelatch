/// Clones the corpus at its pinned SHA and resolves its dependencies.
///
/// Usage, from the stagelatch checkout: `dart run benchmark/bin/setup.dart`.
/// Running it twice is a no-op.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/proc.dart';
import 'package:stagelatch_bench/workspace.dart';

Future<void> main() async {
  final ws = BenchWorkspace.find();
  final corpus = Corpus.load(ws);
  final dir = ws.corpusDir;

  if (!Directory(p.join(dir, '.git')).existsSync()) {
    stdout.writeln('Cloning ${corpus.repository} into $dir');
    await run('git', ['clone', '-q', '--no-checkout', corpus.repository, dir]);
  }

  final head = await _head(dir);
  if (head != corpus.sha) {
    // The SHA may be newer than the clone: fetch it explicitly.
    final known = await _hasCommit(dir, corpus.sha);
    if (!known) {
      await run('git', [
        'fetch',
        '-q',
        'origin',
        corpus.sha,
      ], workingDirectory: dir);
    }
    // --detach: the corpus is never on a branch, so nothing can be pushed.
    await run('git', [
      'checkout',
      '-q',
      '--detach',
      '--force',
      corpus.sha,
    ], workingDirectory: dir);
    stdout.writeln('Checked out ${corpus.sha}');
  }

  final flutter = p.join(Corpus.flutterSdk(corpus.flutter), 'bin', 'flutter');
  if (!File(flutter).existsSync()) {
    stderr.writeln(
      'Flutter ${corpus.flutter} is not installed. '
      'Run: fvm install ${corpus.flutter}',
    );
    exitCode = 1;
    return;
  }

  final packageDir = p.normalize(p.join(dir, corpus.packageDir));
  final config = File(p.join(packageDir, '.dart_tool', 'package_config.json'));
  final lock = File(p.join(packageDir, 'pubspec.lock'));
  final resolvedBy = File(
    p.join(packageDir, '.dart_tool', 'stagelatch_bench_flutter'),
  );
  final upToDate =
      config.existsSync() &&
      resolvedBy.existsSync() &&
      resolvedBy.readAsStringSync() == corpus.flutter &&
      !config.lastModifiedSync().isBefore(lock.lastModifiedSync());
  if (upToDate) {
    stdout.writeln(
      'Corpus ready at ${corpus.sha} (Flutter ${corpus.flutter}).',
    );
    return;
  }

  stdout.writeln('Running pub get with Flutter ${corpus.flutter}');
  // --enforce-lockfile: resolve exactly the versions the corpus pins, so
  // every machine analyzes the same dependency set.
  await run(flutter, [
    'pub',
    'get',
    '--enforce-lockfile',
  ], workingDirectory: packageDir);
  resolvedBy.writeAsStringSync(corpus.flutter);
  stdout.writeln('Corpus ready at ${corpus.sha} (Flutter ${corpus.flutter}).');
}

Future<String> _head(String dir) async {
  try {
    return (await run('git', [
      'rev-parse',
      '--verify',
      '-q',
      'HEAD',
    ], workingDirectory: dir)).trim();
  } on ProcessException {
    return '';
  }
}

Future<bool> _hasCommit(String dir, String sha) async {
  try {
    // ^{commit}: true only when the object exists and is a commit.
    await run('git', [
      'cat-file',
      '-e',
      '$sha^{commit}',
    ], workingDirectory: dir);
    return true;
  } on ProcessException {
    return false;
  }
}

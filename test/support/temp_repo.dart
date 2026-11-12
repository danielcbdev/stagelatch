import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A real git repository in a temporary directory, for adapter and
/// acceptance tests.
///
/// It is isolated from the machine: every `GIT_*` variable of the parent
/// process is dropped, and global and system git configuration are
/// replaced by an empty file, so a test never depends on who runs it.
final class TempRepo {
  new _(this.root, this._base, this.environment);

  /// Creates a repository on branch `main`.
  ///
  /// With [initialCommit], the repository starts with one commit that adds
  /// `README.md`; without it, the branch is unborn. [gitConfig] is applied
  /// to the repository's local configuration.
  static Future<TempRepo> create({
    bool initialCommit = true,
    Map<String, String> gitConfig = const {},
  }) async {
    final temp = await Directory.systemTemp.createTemp('stagelatch_test_');
    // macOS hands out /var/..., a symlink to /private/var/...; git reports
    // the resolved form, so tests must use it too.
    final base = temp.resolveSymbolicLinksSync();
    final root = p.join(base, 'repo');
    await Directory(root).create();
    final emptyConfig = p.join(base, 'gitconfig');
    await File(emptyConfig).writeAsString('');

    final repo = TempRepo._(root, base, {
      for (final MapEntry(:key, :value) in Platform.environment.entries)
        if (!key.toUpperCase().startsWith('GIT_')) key: value,
      'GIT_CONFIG_GLOBAL': emptyConfig,
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_TERMINAL_PROMPT': '0',
    });

    await repo.git(['init', '--quiet', '--initial-branch=main']);
    final config = {
      'user.name': 'Test Author',
      'user.email': 'test@example.com',
      'commit.gpgsign': 'false',
      'core.autocrlf': 'false',
      ...gitConfig,
    };
    for (final MapEntry(:key, :value) in config.entries) {
      await repo.git(['config', key, value]);
    }
    if (initialCommit) {
      await repo.write('README.md', 'test repository\n');
      await repo.stage('README.md');
      await repo.commit('initial commit');
    }
    return repo;
  }

  /// The work tree, with symlinks resolved.
  final String root;

  /// The environment git must be run with to stay isolated.
  final Map<String, String> environment;

  final String _base;

  /// Writes [content] to [path] in the working tree, creating directories.
  Future<void> write(String path, String content) =>
      writeBytes(path, utf8.encode(content));

  /// Writes [bytes] to [path] in the working tree, creating directories.
  Future<void> writeBytes(String path, List<int> bytes) async {
    final file = File(p.join(root, path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  /// The working tree content of [path].
  Future<String> read(String path) => File(p.join(root, path)).readAsString();

  /// Deletes [path] from the working tree.
  Future<void> delete(String path) => File(p.join(root, path)).delete();

  /// Stages the working tree state of [path].
  Future<void> stage(String path) => git(['add', '--', path]);

  /// Puts [content] in the index for [path] without touching the working
  /// tree. This is how partial staging (`git add -p`) is reproduced exactly.
  Future<void> stageContent(String path, String content) async {
    final blob = await git(['hash-object', '-w', '--stdin'], stdin: content);
    await git([
      'update-index',
      '--add',
      '--cacheinfo',
      '100644,${blob.trim()},$path',
    ]);
  }

  /// Commits the index.
  Future<void> commit(String message) =>
      git(['commit', '--quiet', '-m', message]);

  /// Runs git in the repository and returns its standard output.
  ///
  /// Throws [StateError] with git's error output when it exits non-zero.
  Future<String> git(
    List<String> args, {
    String? stdin,
    Map<String, String> env = const {},
  }) async {
    final process = await Process.start(
      'git',
      args,
      workingDirectory: root,
      environment: {...environment, ...env},
      includeParentEnvironment: false,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    if (stdin != null) process.stdin.write(stdin);
    await process.stdin.close();
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw StateError(
        'git ${args.join(' ')} exited with $exitCode: ${await stderr}',
      );
    }
    return await stdout;
  }

  /// Removes the repository from disk.
  Future<void> dispose() async {
    // Windows can hold a file lock for a moment after a process exits.
    for (var attempt = 1; ; attempt++) {
      try {
        await Directory(_base).delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt == 5) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }
}

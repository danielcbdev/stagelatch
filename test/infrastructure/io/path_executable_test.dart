import 'package:path/path.dart' as p;
import 'package:stagelatch/src/infrastructure/io/path_executable.dart';
import 'package:test/test.dart';

void main() {
  group('resolvePathExecutable', () {
    test('skips empty, dot and relative PATH entries', () {
      final found = resolvePathExecutable(
        name: 'git',
        pathEntries: const ['', '.', 'rel/bin', '/safe/bin'],
        repoRoot: '/repo',
        fileExists: (path) => path == p.join('/safe/bin', 'git'),
        realPath: (path) => path,
      );

      expect(found, p.join('/safe/bin', 'git'));
    });

    test('skips PATH directories inside the repository', () {
      final found = resolvePathExecutable(
        name: 'git',
        pathEntries: const ['/repo/bin', '/repo', '/outside/bin'],
        repoRoot: '/repo',
        fileExists: (path) =>
            path == p.join('/repo/bin', 'git') ||
            path == p.join('/outside/bin', 'git'),
        realPath: (path) => path,
      );

      expect(found, p.join('/outside/bin', 'git'));
    });

    test('prefers the first absolute PATH hit', () {
      final found = resolvePathExecutable(
        name: 'git',
        pathEntries: const ['/first/bin', '/second/bin'],
        repoRoot: '/repo',
        fileExists: (path) =>
            path == p.join('/first/bin', 'git') ||
            path == p.join('/second/bin', 'git'),
        realPath: (path) => path,
      );

      expect(found, p.join('/first/bin', 'git'));
    });

    test('returns an absolute path', () {
      final found = resolvePathExecutable(
        name: 'git',
        pathEntries: const ['/usr/bin'],
        repoRoot: '/repo',
        fileExists: (path) => path == p.join('/usr/bin', 'git'),
        realPath: (path) => path,
      );

      expect(found, isNotNull);
      expect(p.isAbsolute(found!), isTrue);
    });

    test('returns null when nothing matches', () {
      final found = resolvePathExecutable(
        name: 'git',
        pathEntries: const ['.', '/missing/bin'],
        repoRoot: '/repo',
        fileExists: (_) => false,
        realPath: (path) => path,
      );

      expect(found, isNull);
    });

    test('on Windows tries PATHEXT suffixes', () {
      final found = resolvePathExecutable(
        name: 'git',
        pathEntries: const [r'C:\Program Files\Git\cmd'],
        repoRoot: r'C:\repo',
        isWindows: true,
        pathExtensions: const ['.EXE', '.BAT'],
        fileExists: (path) => path == r'C:\Program Files\Git\cmd\git.EXE',
        realPath: (path) => path,
        context: p.windows,
      );

      expect(found, r'C:\Program Files\Git\cmd\git.EXE');
    });

    test('leaves a name that already has a separator unchanged', () {
      final found = resolvePathExecutable(
        name: r'C:\tools\git.exe',
        pathEntries: const [r'C:\other'],
        repoRoot: r'C:\repo',
        isWindows: true,
        context: p.windows,
      );

      expect(found, r'C:\tools\git.exe');
    });
  });
}

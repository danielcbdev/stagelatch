import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/environment.dart';
import 'package:stagelatch/src/infrastructure/io/local_doctor_probes.dart';
import 'package:test/test.dart';

import '../../support/temp_repo.dart';

void main() {
  late TempRepo repo;

  setUp(() async {
    repo = await TempRepo.create();
  });

  tearDown(() => repo.dispose());

  group('LocalDoctorProbes.resolveOnPath', () {
    test('skips an executable planted inside the repository', () async {
      final bin = p.join(repo.root, 'bin');
      await Directory(bin).create();
      final plantedName = Platform.isWindows ? 'stagelatch.bat' : 'stagelatch';
      final planted = File(p.join(bin, plantedName));
      if (Platform.isWindows) {
        await planted.writeAsString('@echo planted\r\nexit /b 0\r\n');
      } else {
        await planted.writeAsString('#!/bin/sh\nexit 0\n');
        await Process.run('chmod', ['+x', planted.path]);
      }

      final outside = await Directory.systemTemp.createTemp('stagelatch_path_');
      addTearDown(() async {
        if (outside.existsSync()) await outside.delete(recursive: true);
      });
      final safe = File(p.join(outside.path, plantedName));
      if (Platform.isWindows) {
        await safe.writeAsString('@echo safe\r\nexit /b 0\r\n');
      } else {
        await safe.writeAsString('#!/bin/sh\nexit 0\n');
        await Process.run('chmod', ['+x', safe.path]);
      }

      final separator = Platform.isWindows ? ';' : ':';
      final probes = LocalDoctorProbes(
        repoRoot: repo.root,
        environment: Environment(
          workingDirectory: repo.root,
          variables: {
            ...repo.environment,
            'PATH': '$bin$separator${outside.path}',
          },
          stdoutIsTerminal: false,
          stdinIsTerminal: false,
        ),
      );

      final resolved = await probes.resolveOnPath('stagelatch');

      expect(resolved, isNotNull);
      final resolvedReal = File(resolved!).resolveSymbolicLinksSync();
      final safeReal = safe.resolveSymbolicLinksSync();
      expect(p.equals(resolvedReal, safeReal), isTrue);
      expect(p.isWithin(repo.root, resolvedReal), isFalse);
    });
  });
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch/src/application/hooks/hook_name.dart';
import 'package:stagelatch/src/application/hooks/hook_script.dart';
import 'package:test/test.dart';

void main() {
  test('managed marker is the second line contract, not full script bytes', () {
    expect(managedHookMarker, '# stagelatch:managed');
    expect(isManagedHook('#!/bin/sh\n# stagelatch:managed\necho hi\n'), isTrue);
    expect(
      isManagedHook('#!/bin/sh\necho hi\n# stagelatch:managed\n'),
      isFalse,
    );
  });

  test(
    'rendered hook invokes stagelatch run <hook> with Windows fallbacks',
    () {
      final script = renderHookScript(HookName.preCommit);

      expect(script, contains(managedHookMarker));
      expect(script, contains(r'exec stagelatch run pre-commit "$@"'));
      expect(script, contains(r'exec stagelatch.bat run pre-commit "$@"'));
      expect(
        script,
        contains(r'exec dart pub global run stagelatch run pre-commit "$@"'),
      );
      expect(script, contains('stagelatch not found; skipping.'));
      expect(script.trimRight().endsWith('exit 0'), isTrue);
    },
  );

  test(
    'missing tool is non-blocking (exit 0)',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'stagelatch-hook-compat',
      );
      addTearDown(() => dir.delete(recursive: true));
      final scriptPath = p.join(dir.path, 'pre-commit');
      await File(scriptPath)
          .writeAsString(renderHookScript(HookName.preCommit));

      final result = await Process.run(
        '/bin/sh',
        [scriptPath],
        environment: {'PATH': p.join(dir.path, 'empty-bin')},
        includeParentEnvironment: false,
      );

      expect(result.exitCode, 0);
      expect(result.stderr.toString(), contains('stagelatch not found'));
    },
    tags: ['git'],
    skip: Platform.isWindows ? 'requires /bin/sh' : false,
  );
}

import 'dart:io';

import 'package:stagelatch/src/application/hooks/hook_name.dart';
import 'package:stagelatch/src/application/hooks/hook_script.dart';
import 'package:test/test.dart';

void main() {
  test('the pre-commit script is exactly the text of the spec', () {
    expect(
      renderHookScript(HookName.preCommit),
      File('test/goldens/hooks/pre-commit.sh').readAsStringSync(),
    );
  });

  test('the script uses LF only and ends with one newline', () {
    final script = renderHookScript(HookName.prePush);

    expect(script.contains('\r'), isFalse);
    expect(script.endsWith('exit 0\n'), isTrue);
    expect(script, contains(r'run pre-push "$@"'));
  });

  test('managed means the second line is the marker', () {
    expect(isManagedHook('#!/bin/sh\n# stagelatch:managed\n'), isTrue);
    expect(
      isManagedHook('#!/bin/sh\necho hi\n# stagelatch:managed\n'),
      isFalse,
    );
    expect(isManagedHook('#!/bin/sh\n'), isFalse);
    expect(isManagedHook(''), isFalse);
  });
}

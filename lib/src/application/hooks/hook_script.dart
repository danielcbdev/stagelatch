/// The hook script template (docs/specs/git.md section 7).
library;

import 'package:stagelatch/src/application/hooks/hook_name.dart';

/// The script of section 7, with `<hook>` still in place.
///
/// Line endings are LF. The only substitution [renderHookScript] makes is
/// the hook name, which comes from [HookName] and never from user input
/// (security rule S12).
const _template = r'''
#!/bin/sh
# stagelatch:managed
if command -v stagelatch >/dev/null 2>&1; then
  exec stagelatch run <hook> "$@"
elif command -v stagelatch.bat >/dev/null 2>&1; then
  exec stagelatch.bat run <hook> "$@"
elif command -v dart >/dev/null 2>&1 &&
  dart pub global list 2>/dev/null | grep -q '^stagelatch '; then
  exec dart pub global run stagelatch run <hook> "$@"
fi
echo "stagelatch not found; skipping. Install: dart pub global activate stagelatch" >&2
exit 0
''';

/// The second line of a script this tool owns.
const managedHookMarker = '# stagelatch:managed';

/// The script git should run for [hook].
///
/// The result uses LF line endings and ends with one newline, on every
/// platform. A CRLF script fails in Git for Windows with `\\r: command
/// not found`.
String renderHookScript(HookName hook) =>
    _template.replaceAll('<hook>', hook.fileName);

/// Whether [content] is a script this tool may overwrite or remove.
///
/// Managed means the second line is exactly [managedHookMarker]. A marker
/// anywhere else, including later in a third-party script, does not count
/// (security rule S12).
bool isManagedHook(String content) {
  final firstBreak = content.indexOf('\n');
  if (firstBreak < 0) return false;
  final secondBreak = content.indexOf('\n', firstBreak + 1);
  final secondLine = secondBreak < 0
      ? content.substring(firstBreak + 1)
      : content.substring(firstBreak + 1, secondBreak);
  return secondLine == managedHookMarker;
}

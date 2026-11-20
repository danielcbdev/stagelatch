/// The standard input of a `pre-push` hook (docs/specs/git.md, section 4.2).
library;

import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/errors.dart';

/// One [PushedRef] per non-blank line of [stdin], in order.
///
/// Each line is `<local ref> <local sha> <remote ref> <remote sha>`. A
/// trailing `\r` is dropped. Any other shape is a [UsageException]: a wrong
/// guess about what is being pushed would judge the wrong commits.
List<PushedRef> parsePushedRefs(String stdin) => [
  for (final raw in stdin.split('\n'))
    if (raw.trimRight() case final line when line.isNotEmpty) _parse(line),
];

PushedRef _parse(String line) {
  final fields = line.split(' ');
  if (fields.length != 4 || fields.any((field) => field.isEmpty)) {
    throw UsageException('Malformed pre-push input: "$line".');
  }
  return PushedRef(
    localRef: fields[0],
    localSha: fields[1],
    remoteRef: fields[2],
    remoteSha: fields[3],
  );
}

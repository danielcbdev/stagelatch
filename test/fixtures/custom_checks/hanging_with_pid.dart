import 'dart:convert';
import 'dart:io';

/// Writes its own process id to the file named by the first argument, then
/// accepts init and never answers. AC-31 uses the id to prove that the host
/// killed the child after the timeout.
void main(List<String> args) async {
  File(args.first).writeAsStringSync('$pid');
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    jsonDecode(line);
    await Future<void>.delayed(const Duration(days: 1));
  }
}

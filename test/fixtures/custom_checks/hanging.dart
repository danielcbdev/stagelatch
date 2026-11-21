import 'dart:convert';
import 'dart:io';

/// Accepts init and never answers.
void main() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    jsonDecode(line);
    await Future<void>.delayed(const Duration(days: 1));
  }
}

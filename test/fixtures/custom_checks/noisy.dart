import 'dart:convert';
import 'dart:io';

/// Prints non-protocol text on stdout before answering.
void main() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final message = jsonDecode(line) as Map<String, Object?>;
    if (message['type'] == 'init') {
      stdout
        ..writeln('stray print from the child')
        ..writeln(
          jsonEncode({
            'type': 'ready',
            'protocol': 1,
            'rules': [
              {'id': 'fixture/ok', 'summary': 'x'},
            ],
          }),
        );
    }
  }
}

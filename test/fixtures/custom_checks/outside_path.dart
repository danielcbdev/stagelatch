import 'dart:convert';
import 'dart:io';

/// Reports a finding whose path escapes the repository.
void main() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final message = jsonDecode(line) as Map<String, Object?>;
    switch (message['type']) {
      case 'init':
        stdout.writeln(
          jsonEncode({
            'type': 'ready',
            'protocol': 1,
            'rules': [
              {'id': 'fixture/ok', 'summary': 'ok'},
            ],
          }),
        );
      case 'run':
        stdout
          ..writeln(
            jsonEncode({
              'type': 'finding',
              'rule': 'fixture/ok',
              'path': '../secret',
              'line': 1,
              'column': 1,
              'message': 'outside',
            }),
          )
          ..writeln(jsonEncode({'type': 'done'}));
        return;
    }
  }
}

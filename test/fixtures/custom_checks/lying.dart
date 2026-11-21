import 'dart:convert';
import 'dart:io';

/// Declares one rule and reports another.
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
              'rule': 'fixture/undeclared',
              'path': 'lib/a.dart',
              'line': 1,
              'column': 1,
              'message': 'lie',
            }),
          )
          ..writeln(jsonEncode({'type': 'done'}));
        return;
    }
  }
}

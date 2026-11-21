import 'dart:convert';
import 'dart:io';

/// Speaks protocol 1: ready → optional finding → done.
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
              {
                'id': 'fixture/ok',
                'summary': 'Always ok',
                'defaultSeverity': 'error',
              },
            ],
          }),
        );
      case 'run':
        stdout
          ..writeln(
            jsonEncode({
              'type': 'finding',
              'rule': 'fixture/ok',
              'path': 'lib/a.dart',
              'line': 1,
              'column': 1,
              'message': 'hello',
            }),
          )
          ..writeln(jsonEncode({'type': 'done'}));
        return;
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:example_custom_check/no_print.dart';

/// Speaks stagelatch custom-check protocol 1 (`example/no-print`).
void main() async {
  final pending = <int, String>{};
  var nextReadId = 1;
  var expectingRun = false;

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
                'id': 'example/no-print',
                'summary': 'Disallow print() in changed Dart files',
                'defaultSeverity': 'error',
              },
            ],
          }),
        );
        expectingRun = true;
      case 'run':
        if (!expectingRun) {
          continue;
        }
        expectingRun = false;
        final changes = (message['changes']! as List<Object?>)
            .cast<Map<String, Object?>>();
        for (final change in changes) {
          final path = change['path']! as String;
          final kind = change['kind']! as String;
          if (kind == 'deleted' || !path.endsWith('.dart')) {
            continue;
          }
          final id = nextReadId++;
          pending[id] = path;
          stdout.writeln(
            jsonEncode({
              'type': 'read',
              'id': id,
              'path': path,
              'side': 'snapshot',
            }),
          );
        }
        if (pending.isEmpty) {
          stdout.writeln(jsonEncode({'type': 'done'}));
          return;
        }
      case 'content':
        final id = message['id']! as int;
        final path = pending.remove(id);
        if (path == null) {
          continue;
        }
        final text = message['text'];
        if (text is String) {
          final hit = findPrintCall(text);
          if (hit != null) {
            stdout.writeln(
              jsonEncode({
                'type': 'finding',
                'rule': 'example/no-print',
                'path': path,
                'line': hit.line,
                'column': hit.column,
                'message': 'Avoid print(); use a logger or remove the call.',
              }),
            );
          }
        }
        if (pending.isEmpty) {
          stdout.writeln(jsonEncode({'type': 'done'}));
          return;
        }
    }
  }
}

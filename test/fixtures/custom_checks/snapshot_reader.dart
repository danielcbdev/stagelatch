import 'dart:convert';
import 'dart:io';

/// Speaks protocol 1 as the check `probe`: reads every changed Dart file
/// through `read` and reports `probe/forbidden` on the first line that
/// contains `FORBIDDEN`. What it sees is what the host served, so the
/// acceptance tests can tell the snapshot from the working tree.
void main() async {
  final pending = <int, String>{};
  var nextId = 1;
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final message = jsonDecode(line) as Map<String, Object?>;
    switch (message['type']) {
      case 'init':
        await _emit({
          'type': 'ready',
          'protocol': 1,
          'rules': [
            {
              'id': 'probe/forbidden',
              'summary': 'No FORBIDDEN marker in changed Dart files',
              'defaultSeverity': 'error',
            },
          ],
        });
      case 'run':
        final changes = (message['changes']! as List<Object?>)
            .cast<Map<String, Object?>>();
        for (final change in changes) {
          final path = change['path']! as String;
          if (change['kind'] == 'deleted' || !path.endsWith('.dart')) {
            continue;
          }
          final id = nextId++;
          pending[id] = path;
          await _emit({
            'type': 'read',
            'id': id,
            'path': path,
            'side': 'snapshot',
          });
        }
        if (pending.isEmpty) {
          await _emit({'type': 'done'});
          return;
        }
      case 'content':
        final path = pending.remove(message['id']! as int);
        final text = message['text'];
        if (path != null && text is String) {
          final lines = const LineSplitter().convert(text);
          for (var i = 0; i < lines.length; i++) {
            final column = lines[i].indexOf('FORBIDDEN');
            if (column >= 0) {
              await _emit({
                'type': 'finding',
                'rule': 'probe/forbidden',
                'path': path,
                'line': i + 1,
                'column': column + 1,
                'message': 'FORBIDDEN marker found.',
              });
              break;
            }
          }
        }
        if (pending.isEmpty) {
          await _emit({'type': 'done'});
          return;
        }
    }
  }
}

/// Writes one protocol line and flushes (piped stdout can buffer).
Future<void> _emit(Map<String, Object?> message) async {
  stdout.writeln(jsonEncode(message));
  await stdout.flush();
}

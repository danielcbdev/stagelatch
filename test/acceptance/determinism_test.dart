import 'dart:convert';

import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

/// [json] with every `durationMs` field removed, re-encoded.
String withoutDurations(String json) {
  Object? strip(Object? value) => switch (value) {
    final Map<String, Object?> map => {
      for (final entry in map.entries)
        if (entry.key != 'durationMs') entry.key: strip(entry.value),
    },
    final List<Object?> list => [for (final item in list) strip(item)],
    _ => value,
  };
  return jsonEncode(strip(jsonDecode(json)));
}

void main() {
  // docs/engineering/testing.md, section 5. The shuffled-registry half
  // arrives with several registered checks (plan 02, Task 15).
  test('two runs with --reporter json are byte-identical once durationMs is '
      'removed', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.stageContent('pubspec.yaml', badPubspec);
    const args = ['run', 'pre-commit', '--reporter', 'json'];

    final first = await repo.stagelatch(args);
    final second = await repo.stagelatch(args);

    expect(first.exitCode, 1);
    expect(withoutDurations(first.stdout), withoutDurations(second.stdout));
    expect(
      (jsonDecode(first.stdout) as Map<String, Object?>)['verdict'],
      'fail',
    );
  });
}

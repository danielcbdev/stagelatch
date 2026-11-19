import 'package:test/test.dart';

import '../support/acceptance.dart';
import '../support/temp_repo.dart';

void main() {
  test('a CRLF pubspec is still judged', () async {
    final repo = await TempRepo.create();
    addTearDown(repo.dispose);
    await repo.stageContent(
      'pubspec.yaml',
      badPubspec.replaceAll('\n', '\r\n'),
    );

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 1);
    expect(result.stdout, contains('pubspec/path-dependency'));
    expect(result.stdout, contains('Commit blocked'));
  });

  test('core.autocrlf does not hide a path dependency', () async {
    final repo = await TempRepo.create(gitConfig: {'core.autocrlf': 'true'});
    addTearDown(repo.dispose);
    await repo.write('pubspec.yaml', badPubspec);
    await repo.stage('pubspec.yaml');

    final result = await repo.stagelatch(['run', 'pre-commit']);

    expect(result.exitCode, 1);
    expect(result.stdout, contains('pubspec/path-dependency'));
  });
}

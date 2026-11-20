import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/hooks/pushed_refs.dart';
import 'package:test/test.dart';

void main() {
  test('parses one ref per line and rejects malformed lines', () {
    final refs = parsePushedRefs('refs/heads/f aaa refs/heads/f bbb\n');

    expect(refs.single.localRef, 'refs/heads/f');
    expect(refs.single.localSha, 'aaa');
    expect(refs.single.remoteRef, 'refs/heads/f');
    expect(refs.single.remoteSha, 'bbb');
    expect(
      () => parsePushedRefs('too few\n'),
      throwsA(
        isA<UsageException>().having(
          (e) => e.message,
          'message',
          'Malformed pre-push input: "too few".',
        ),
      ),
    );
    expect(parsePushedRefs(''), isEmpty);
  });

  test('keeps the order of the lines and ignores blank lines and CR', () {
    final refs = parsePushedRefs(
      'refs/heads/b 1 refs/heads/b 2\r\n\nrefs/heads/a 3 refs/heads/a 4\r\n',
    );

    expect(refs.map((ref) => ref.localRef), ['refs/heads/b', 'refs/heads/a']);
    expect(refs.last.remoteSha, '4');
  });

  test('five fields are malformed too', () {
    expect(
      () => parsePushedRefs('a b c d e\n'),
      throwsA(isA<UsageException>()),
    );
  });
}

import 'package:stagelatch/src/application/text/sanitize.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeForTerminal', () {
    test('removes escape sequences introducers and other C0 controls', () {
      expect(sanitizeForTerminal('a\u001b[31mb\u0007c'), 'a[31mbc');
      expect(sanitizeForTerminal('a\u0000b\u0008c\u007fd'), 'abcd');
    });

    test('removes C1 controls, which some terminals also interpret', () {
      expect(sanitizeForTerminal('a\u009b31mb\u0085c'), 'a31mbc');
    });

    test('turns newlines and tabs into single spaces', () {
      expect(sanitizeForTerminal('line\nbreak\ttab'), 'line break tab');
      expect(sanitizeForTerminal('windows\r\nending'), 'windows ending');
    });

    test('removes bidirectional overrides that can reorder what is shown', () {
      expect(sanitizeForTerminal('a\u202Eb\u2066c\u2069d\u200Fe'), 'abcde');
    });

    test('keeps printable text, including non-ASCII letters and emoji', () {
      expect(sanitizeForTerminal('ação.dart'), 'ação.dart');
      expect(sanitizeForTerminal('日本語 😀 ok'), '日本語 😀 ok');
      expect(sanitizeForTerminal(r'a b"c\d'), r'a b"c\d');
    });

    test('returns an empty string unchanged', () {
      expect(sanitizeForTerminal(''), '');
    });

    test('handles a megabyte of control characters', () {
      expect(sanitizeForTerminal('\u001b' * (1 << 20)), '');
    });
  });
}

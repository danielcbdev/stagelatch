import 'package:stagelatch/src/checks/assets/format_size.dart';
import 'package:test/test.dart';

void main() {
  const kb = 1024;
  const mb = 1024 * 1024;

  group('formatSize', () {
    test('uses the unit of the limit, with one decimal', () {
      expect(formatSize(627098, limit: 500 * kb), '612.4KB');
      expect(formatSize(1572864, limit: mb), '1.5MB');
      expect(formatSize(2000, limit: 100), '2000.0B');
    });

    test('rounds half up to one decimal', () {
      // 1023 bytes is 0.999 KB.
      expect(formatSize(1023, limit: kb), '1.0KB');
      // 1,100,000 bytes is 1.0490 MB.
      expect(formatSize(1100000, limit: mb), '1.0MB');
    });

    test('a larger unit starts at exactly one of the smaller one', () {
      expect(formatSize(1024 * kb, limit: 1024 * kb), '1.0MB');
      expect(formatSize(1024 * kb, limit: 1023 * kb), '1024.0KB');
    });

    test('knows gigabytes', () {
      expect(formatSize(3 * 1024 * mb, limit: 1024 * mb), '3.0GB');
    });
  });

  group('formatLimit', () {
    test('prints a whole number of its unit without a decimal', () {
      expect(formatLimit(500 * kb), '500KB');
      expect(formatLimit(mb), '1MB');
      expect(formatLimit(100), '100B');
    });

    test('prints one decimal when the limit is not whole in its unit', () {
      expect(formatLimit(1536 * kb), '1.5MB');
      expect(formatLimit(1500), '1.5KB');
    });

    test('a limit of zero is zero bytes', () {
      expect(formatLimit(0), '0B');
    });
  });
}

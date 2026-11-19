import 'package:stagelatch/src/application/config/value_parsers.dart';
import 'package:test/test.dart';

void main() {
  group('parseSize', () {
    test('uses binary units', () {
      expect(parseSize('10B'), 10);
      expect(parseSize('500KB'), 512000);
      expect(parseSize('1MB'), 1048576);
      expect(parseSize('0B'), 0);
    });

    test('rejects anything else', () {
      const invalid = [
        '',
        '5',
        'KB',
        '-1KB',
        '1.5MB',
        '1 KB',
        '1kb',
        '1GB',
        ' 1KB',
        '1KB ',
        '99999999999999999999MB',
      ];
      for (final value in invalid) {
        expect(
          () => parseSize(value),
          throwsFormatException,
          reason: '"$value" must be rejected',
        );
      }
    });
  });

  group('parseDuration', () {
    test('accepts whole milliseconds and decimal seconds', () {
      expect(parseDuration('2s'), const Duration(seconds: 2));
      expect(parseDuration('1.5s'), const Duration(milliseconds: 1500));
      expect(parseDuration('250ms'), const Duration(milliseconds: 250));
      expect(parseDuration('0.001s'), const Duration(milliseconds: 1));
    });

    test('rejects zero, missing units and anything else', () {
      const invalid = [
        '',
        '0s',
        '0ms',
        '0.0s',
        '2',
        's',
        'ms',
        '1.5ms',
        '-1s',
        '1 s',
        '1S',
        '1m',
        '1.s',
        '.5s',
      ];
      for (final value in invalid) {
        expect(
          () => parseDuration(value),
          throwsFormatException,
          reason: '"$value" must be rejected',
        );
      }
    });
  });
}

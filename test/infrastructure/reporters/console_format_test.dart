import 'package:stagelatch/src/infrastructure/reporters/console_format.dart';
import 'package:test/test.dart';

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

void main() {
  group('formatDuration', () {
    test('uses milliseconds below one second', () {
      expect(formatDuration(_ms(0)), '0ms');
      expect(formatDuration(_ms(6)), '6ms');
      expect(formatDuration(_ms(999)), '999ms');
    });

    test('uses seconds with one decimal from one second on', () {
      expect(formatDuration(_ms(1000)), '1.0s');
      expect(formatDuration(_ms(1049)), '1.0s');
      expect(formatDuration(_ms(1050)), '1.1s');
      expect(formatDuration(_ms(12349)), '12.3s');
      expect(formatDuration(_ms(59999)), '60.0s');
    });
  });

  group('formatSeconds', () {
    test('always uses seconds with one decimal', () {
      expect(formatSeconds(_ms(40)), '0.0s');
      expect(formatSeconds(_ms(120)), '0.1s');
      expect(formatSeconds(_ms(917)), '0.9s');
      expect(formatSeconds(_ms(950)), '1.0s');
      expect(formatSeconds(_ms(13600)), '13.6s');
    });
  });

  group('formatBudget', () {
    test('prints whole seconds as seconds and anything else in ms', () {
      expect(formatBudget(_ms(2000)), '2s');
      expect(formatBudget(_ms(1500)), '1500ms');
      expect(formatBudget(_ms(250)), '250ms');
    });
  });

  group('counted', () {
    test('uses the singular for exactly one', () {
      expect(counted(1, 'file'), '1 file');
      expect(counted(0, 'error'), '0 errors');
      expect(counted(2, 'warning'), '2 warnings');
    });

    test('uses an irregular plural when given', () {
      expect(counted(2, 'entry', plural: 'entries'), '2 entries');
      expect(counted(1, 'entry', plural: 'entries'), '1 entry');
    });
  });
}

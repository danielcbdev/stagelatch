import 'package:stagelatch/src/application/environment.dart';
import 'package:test/test.dart';

Environment _env({
  bool tty = true,
  Map<String, String> variables = const {},
  bool? colorOverride,
}) => Environment(
  workingDirectory: '/repo',
  variables: variables,
  stdoutIsTerminal: tty,
  stdinIsTerminal: tty,
  colorOverride: colorOverride,
);

void main() {
  group('Environment.useColor', () {
    test('is on for a terminal without NO_COLOR', () {
      expect(_env().useColor, isTrue);
    });

    test('is off when stdout is not a terminal', () {
      expect(_env(tty: false).useColor, isFalse);
    });

    test('is off when NO_COLOR has a value', () {
      expect(_env(variables: {'NO_COLOR': '1'}).useColor, isFalse);
    });

    test('ignores an empty NO_COLOR, as the convention says', () {
      expect(_env(variables: {'NO_COLOR': ''}).useColor, isTrue);
    });

    test('follows an explicit override in both directions', () {
      expect(_env(tty: false, colorOverride: true).useColor, isTrue);
      expect(
        _env(variables: {'NO_COLOR': '1'}, colorOverride: true).useColor,
        isTrue,
      );
      expect(_env(colorOverride: false).useColor, isFalse);
    });
  });

  group('Environment', () {
    test('keeps its own unmodifiable copy of the variables', () {
      final source = {'HOME': '/home/dev'};
      final environment = _env(variables: source);

      source['HOME'] = '/elsewhere';

      expect(environment.variables['HOME'], '/home/dev');
      expect(() => environment.variables['X'] = 'y', throwsUnsupportedError);
    });

    test('exposes the values it was built from', () {
      final environment = Environment(
        workingDirectory: '/repo',
        variables: const {},
        stdoutIsTerminal: true,
        stdinIsTerminal: false,
      );

      expect(environment.workingDirectory, '/repo');
      expect(environment.stdoutIsTerminal, isTrue);
      expect(environment.stdinIsTerminal, isFalse);
      expect(environment.colorOverride, isNull);
    });
  });
}

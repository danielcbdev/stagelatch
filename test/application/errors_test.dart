import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:test/test.dart';

void main() {
  test('every failure is a StagelatchException and an Exception', () {
    const failures = <Object>[
      UsageException('u'),
      ConfigException('c'),
      InternalException('i'),
    ];

    for (final failure in failures) {
      expect(failure, isA<StagelatchException>());
      expect(failure, isA<Exception>());
    }
  });

  group('UsageException', () {
    test('prints its message', () {
      expect(
        const UsageException('Unknown hook "x".').toString(),
        'Unknown hook "x".',
      );
    });
  });

  group('ConfigException', () {
    test('prints file, line and column before the message', () {
      final error = ConfigException(
        'Unknown key "forbid" under "pubspec".',
        location: Location(
          RepoPath('stagelatch.yaml'),
          const Position(2, 3),
          const Position(2, 9),
        ),
      );

      expect(
        error.toString(),
        'stagelatch.yaml:2:3: Unknown key "forbid" under "pubspec".',
      );
      expect(error.message, 'Unknown key "forbid" under "pubspec".');
    });

    test('prints only the message when it has no location', () {
      const error = ConfigException('custom_checks requires stagelatch.');

      expect(error.toString(), 'custom_checks requires stagelatch.');
      expect(error.location, isNull);
    });
  });

  group('InternalException', () {
    test('keeps where it happened, the cause and the stack trace', () {
      final cause = StateError('boom');
      final stackTrace = StackTrace.current;
      final error = InternalException(
        'Bad state: boom',
        where: 'check "pubspec"',
        cause: cause,
        stackTrace: stackTrace,
      );

      expect(error.message, 'Bad state: boom');
      expect(error.where, 'check "pubspec"');
      expect(error.cause, same(cause));
      expect(error.stackTrace, same(stackTrace));
      expect(error.toString(), 'Bad state: boom');
    });

    test('needs only a message', () {
      const error = InternalException('git exited with 128');

      expect(error.where, isNull);
      expect(error.cause, isNull);
      expect(error.stackTrace, isNull);
    });
  });
}

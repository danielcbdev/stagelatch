import 'package:stagelatch/src/application/ports/clock.dart';

/// A [Clock] that only moves when a test tells it to.
final class FakeClock implements Clock {
  @override
  Duration elapsed = Duration.zero;

  /// Moves the clock forward by [duration].
  void advance(Duration duration) => elapsed += duration;
}

/// The clock the real pipeline measures with.
library;

import 'package:stagelatch/src/application/ports/clock.dart';

/// A [Stopwatch] started when the clock is created.
///
/// Only differences of [elapsed] are meaningful (ADR-0003).
final class SystemClock implements Clock {
  /// Starts the clock.
  new() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  @override
  Duration get elapsed => _watch.elapsed;
}

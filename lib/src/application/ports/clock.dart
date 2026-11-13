/// The port through which use cases measure time.
library;

/// A monotonic clock.
///
/// The pipeline reports how long each check took, but nothing may read the
/// system clock directly: with the clock injected, tests are instant and
/// durations are the only non-deterministic part of a report (ADR-0003).
abstract interface class Clock {
  /// The time elapsed since some fixed moment in the past. It never goes
  /// backwards; only differences between two readings are meaningful.
  Duration get elapsed;
}

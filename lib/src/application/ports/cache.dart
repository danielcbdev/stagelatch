/// A content-addressed store for values that can be recomputed.
library;

/// A store of strings under a namespace and a key.
///
/// It is an optimization, never a source of truth: a value that is missing,
/// unreadable or stale is recomputed, so an implementation that cannot do
/// its job answers null and stores nothing (docs/specs/dart-toolchain.md,
/// section 6.1).
abstract interface class Cache {
  /// The value stored under [namespace] and [key], or null when there is
  /// none or it cannot be read.
  ///
  /// [namespace] matches `[a-z0-9-]+` and [key] `[0-9a-f-]{2,}`; anything
  /// else is an [ArgumentError], because it is a bug and not an I/O failure.
  Future<String?> read(String namespace, String key);

  /// Stores [value] under [namespace] and [key], replacing what is there.
  ///
  /// A failure to store is not an error: the write is abandoned.
  Future<void> write(String namespace, String key, String value);
}

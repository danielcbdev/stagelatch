import 'package:stagelatch/src/application/ports/cache.dart';

/// An in-memory [Cache] that records every call.
final class FakeCache implements Cache {
  /// Creates a cache. With [failing], every call throws.
  new({this.failing = false});

  /// Whether every call throws a [StateError]-free [Exception].
  final bool failing;

  /// What is stored, by `<namespace>/<key>`.
  final Map<String, String> entries = {};

  /// The `<namespace>/<key>` of every read, in call order.
  final List<String> reads = [];

  /// The `<namespace>/<key>` of every write, in call order.
  final List<String> writes = [];

  @override
  Future<String?> read(String namespace, String key) async {
    reads.add('$namespace/$key');
    if (failing) throw const FormatException('the cache is broken');
    return entries['$namespace/$key'];
  }

  @override
  Future<void> write(String namespace, String key, String value) async {
    writes.add('$namespace/$key');
    if (failing) throw const FormatException('the cache is broken');
    entries['$namespace/$key'] = value;
  }
}

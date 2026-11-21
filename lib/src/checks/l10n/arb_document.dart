/// A parsed `.arb` file, seen through the questions rules ask of it.
library;

import 'package:stagelatch/src/domain/documents.dart';

/// An ARB file whose root is a JSON object.
///
/// An ARB file mixes messages with metadata: `@@locale`, and `@key` entries
/// that describe the message `key`. Only the messages matter to the rules,
/// so keys that start with `@` are left out.
final class ArbDocument {
  /// Wraps the root object of a parsed `.arb` file.
  new(LocatedMap root)
    : messages = Map.unmodifiable({
        for (final MapEntry(:key, :value) in root.entries.entries)
          if (!key.startsWith('@')) key: value,
      });

  /// The messages by key, in document order, each with the location of its
  /// key. The value is a string for an ordinary message.
  final Map<String, LocatedEntry> messages;
}

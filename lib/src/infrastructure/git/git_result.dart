/// The outcome of one finished git command.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:stagelatch/src/application/errors.dart';

/// What a git command printed and how it exited.
final class GitResult {
  /// Creates a result.
  const new({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The exit code. Always one the caller declared as expected.
  final int exitCode;

  /// Standard output, as raw bytes.
  final Uint8List stdout;

  /// Standard error, decoded leniently; for error messages only.
  final String stderr;

  /// Standard output as text, for output that carries no path: object ids,
  /// booleans, ref names. Malformed bytes become U+FFFD instead of failing.
  String get text => utf8.decode(stdout, allowMalformed: true);

  /// Standard output of a `-z` command, split on NUL.
  ///
  /// `-z` is the only output form that is safe for paths containing
  /// newlines, quotes or non-ASCII characters. The terminator after the
  /// last field is dropped; empty fields in between are kept.
  ///
  /// Throws [UsageException], naming the bytes in hexadecimal, when a field
  /// is not valid UTF-8: such a path cannot be represented in reports.
  List<String> get nulSeparated {
    final fields = <String>[];
    var start = 0;
    for (var index = 0; index < stdout.length; index++) {
      if (stdout[index] != 0) continue;
      fields.add(_decode(Uint8List.sublistView(stdout, start, index)));
      start = index + 1;
    }
    if (start < stdout.length) {
      fields.add(_decode(Uint8List.sublistView(stdout, start)));
    }
    return fields;
  }

  static String _decode(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      final hex = bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      throw UsageException(
        'A path in this repository is not valid UTF-8: $hex.',
      );
    }
  }
}

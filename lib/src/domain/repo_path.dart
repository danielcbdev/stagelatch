/// Repository-relative paths.
library;

import 'package:meta/meta.dart';

/// A path relative to the repository root, exactly as git stores it.
///
/// The separator is always `/`, on every platform. A path never starts or
/// ends with `/`, has no empty, `.` or `..` segment, and contains no NUL. A
/// backslash is an ordinary character: git allows it in file names.
///
/// Every path that comes from git or from configuration becomes a [RepoPath]
/// before it is used, so a path can never point outside the repository
/// (security rule S3).
@immutable
final class RepoPath implements Comparable<RepoPath> {
  /// Validates [value] and wraps it.
  ///
  /// Throws [FormatException] when [value] is empty, absolute, ends with a
  /// separator, contains an empty, `.` or `..` segment, or contains NUL.
  factory(String value) {
    if (value.isEmpty) {
      throw const FormatException('A repository path cannot be empty.');
    }
    if (value.contains('\u0000')) {
      throw FormatException('A repository path cannot contain NUL.', value);
    }
    for (final segment in value.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        throw FormatException('Not a clean repository-relative path.', value);
      }
    }
    return RepoPath._(value);
  }

  /// Wraps a value already known to be valid.
  const new _(this.value);

  /// The path, with `/` separators.
  final String value;

  /// The last segment: the file or directory name.
  String get basename => value.substring(value.lastIndexOf('/') + 1);

  /// The extension of [basename], dot included, or `''` when there is none.
  ///
  /// A leading dot does not start an extension: `.env` has none, while
  /// `.env.production` has `.production`.
  String get extension {
    final name = basename;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot);
  }

  /// The containing directory, or null for an entry at the repository root.
  RepoPath? get parent {
    final slash = value.lastIndexOf('/');
    return slash < 0 ? null : RepoPath._(value.substring(0, slash));
  }

  /// Whether this path is inside [directory], at any depth.
  ///
  /// A path is not within itself, and `lib/a.dart` is not within `li`.
  bool isWithin(RepoPath directory) => value.startsWith('${directory.value}/');

  /// Orders by UTF-16 code unit, so the order is identical on every
  /// platform and locale (ADR-0003).
  @override
  int compareTo(RepoPath other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is RepoPath && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

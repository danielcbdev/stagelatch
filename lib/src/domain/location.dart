/// Positions and ranges inside files of a snapshot.
library;

import 'package:meta/meta.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// A character position in a text file. Both axes are 1-based.
@immutable
final class Position implements Comparable<Position> {
  /// Creates a position at [line] and [column], each at least 1.
  const new(this.line, this.column)
    : assert(line >= 1, 'line is 1-based'),
      assert(column >= 1, 'column is 1-based');

  /// The line, counting from 1.
  final int line;

  /// The column, counting from 1, in UTF-16 code units.
  final int column;

  /// Orders by [line], then by [column].
  @override
  int compareTo(Position other) {
    final byLine = line.compareTo(other.line);
    return byLine != 0 ? byLine : column.compareTo(other.column);
  }

  @override
  bool operator ==(Object other) =>
      other is Position && other.line == line && other.column == column;

  @override
  int get hashCode => Object.hash(line, column);

  @override
  String toString() => '$line:$column';
}

/// A range in one file of a snapshot: where a finding points.
@immutable
final class Location {
  /// Creates a location in [path] from [start] to [end].
  ///
  /// [end] is exclusive and is never before [start].
  const new(this.path, this.start, this.end);

  /// A location for a finding that concerns a whole file, such as a
  /// path-based rule: the first character, as an empty range.
  const new wholeFile(RepoPath path)
    : this(path, const Position(1, 1), const Position(1, 1));

  /// The file the range is in.
  final RepoPath path;

  /// The first character of the range.
  final Position start;

  /// The position just after the last character of the range.
  final Position end;

  @override
  bool operator ==(Object other) =>
      other is Location &&
      other.path == path &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(path, start, end);

  /// `path:line:column` of [start], the form editors and terminals link.
  @override
  String toString() => '$path:$start';
}

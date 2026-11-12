/// Syntactic facts about a Dart file (ADR-0013).
library;

import 'package:stagelatch/src/domain/location.dart';

/// The kind of a directive.
enum DirectiveKind {
  /// `import`.
  import,

  /// `export`.
  export,

  /// `part`.
  part,

  /// `part of`.
  partOf,
}

/// One URI named by a directive.
///
/// A conditional import produces one [Directive] per branch.
final class Directive {
  /// Creates a directive fact.
  const new({required this.kind, required this.uri, required this.location});

  /// What the directive is.
  final DirectiveKind kind;

  /// The URI exactly as written in the source.
  final String uri;

  /// Where the directive is.
  final Location location;
}

/// A declaration that carries at least one annotation relevant to code
/// generation.
final class AnnotatedDeclaration {
  /// Creates a declaration fact.
  const new({
    required this.name,
    required this.annotations,
    required this.tokenHash,
    required this.location,
  });

  /// `Order` for a top-level declaration, `Order.fromJson` for a member.
  final String name;

  /// Annotation names as written, without `@` or arguments, sorted.
  final List<String> annotations;

  /// SHA-256, in hexadecimal, of the declaration's tokens joined by one
  /// space. Comments and whitespace are not tokens, so reformatting never
  /// changes it.
  final String tokenHash;

  /// Where the declaration starts.
  final Location location;
}

/// A call to a test function such as `test` or `group`.
final class TestCall {
  /// Creates a test call fact.
  const new({
    required this.function,
    required this.description,
    required this.groups,
    required this.location,
    this.solo,
    this.skip,
  });

  /// The function called: `test`, `group`, `testWidgets`, ...
  final String function;

  /// The description: the literal's value, or the argument's source text
  /// when it is not a string literal.
  final String description;

  /// Descriptions of the enclosing groups, outermost first.
  final List<String> groups;

  /// Where the call is.
  final Location location;

  /// Where a `solo` argument other than the literal `false` is, or null.
  final Location? solo;

  /// Where a `skip` argument other than `false` or `null`, or a `@Skip`
  /// annotation, is; or null.
  final Location? skip;
}

/// Everything a rule may know about a Dart file without resolving it.
///
/// Facts depend only on the file's content, so they are cacheable by blob
/// id. A rule that needs a new fact adds a field here; it never reaches
/// for a parser itself.
final class DartFileFacts {
  /// Creates the facts of one file.
  const new({
    this.directives = const [],
    this.annotatedDeclarations = const [],
    this.testCalls = const [],
    this.identifiers = const {},
  });

  /// Imports, exports and parts, in source order.
  final List<Directive> directives;

  /// Annotated declarations, in source order.
  final List<AnnotatedDeclaration> annotatedDeclarations;

  /// Calls to the configured test functions, in source order.
  final List<TestCall> testCalls;

  /// Every identifier token of the file. Filled from 0.3.0 on.
  final Set<String> identifiers;
}

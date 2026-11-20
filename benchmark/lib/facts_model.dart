/// The facts both extractors produce, in one comparable shape (ADR-0017).
library;

/// Annotation names that never make a declaration "annotated"
/// (`specs/dart-toolchain.md` section 6).
const ignoredAnnotations = {
  'override',
  'protected',
  'visibleForTesting',
  'immutable',
  'Deprecated',
  'deprecated',
};

/// The test functions inspected when nothing else is configured
/// (`specs/config.md`, `tests.functions`).
const defaultTestFunctions = {'test', 'testWidgets', 'group'};

/// The function whose calls open a group.
const groupFunction = 'group';

/// One annotated declaration.
final class DeclFact {
  /// Creates a declaration fact.
  const new({
    required this.name,
    required this.annotations,
    required this.tokenHash,
    required this.line,
    required this.column,
  });

  /// `Order`, or `Order.fromJson` for a member.
  final String name;

  /// Annotation names as written, sorted, ignored ones removed.
  final List<String> annotations;

  /// SHA-256 hex of the token lexemes joined by one space.
  final String tokenHash;

  /// 1-based line of the first token (the first `@`).
  final int line;

  /// 1-based column of the first token.
  final int column;

  /// The canonical comparison line.
  String get canonical =>
      'decl|$name|${annotations.join(',')}|$tokenHash|$line:$column';
}

/// One call to a test function.
final class CallFact {
  /// Creates a test call fact.
  const new({
    required this.function,
    required this.description,
    required this.groups,
    required this.line,
    required this.column,
    this.solo,
    this.skip,
  });

  /// `test`, `group`, ...
  final String function;

  /// The literal's value, or the source text of the argument.
  final String description;

  /// Enclosing group descriptions, outermost first.
  final List<String> groups;

  /// Line of the function name.
  final int line;

  /// Column of the function name.
  final int column;

  /// `line:col` of the `solo` argument, or null.
  final String? solo;

  /// `line:col` of the `skip` argument or `@Skip` annotation, or null.
  final String? skip;

  /// The canonical comparison line.
  String get canonical =>
      'call|$function|${_escape(description)}|'
      '${groups.map(_escape).join('/')}|$line:$column|${solo ?? '-'}|'
      '${skip ?? '-'}';

  static String _escape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('\n', r'\n').replaceAll('|', r'\|');
}

/// Everything an extractor reports for one file.
final class FactsResult {
  /// Creates a result.
  const new({
    required this.declarations,
    required this.calls,
    required this.identifiers,
  });

  /// Annotated declarations, in source order.
  final List<DeclFact> declarations;

  /// Test calls, in source order.
  final List<CallFact> calls;

  /// Every word token of the file, sorted.
  final List<String> identifiers;

  /// The lines to compare, one fact per line. The shipped extractor does
  /// not fill identifiers yet (plan 04), so they are optional.
  List<String> canonical({bool withIdentifiers = true}) => [
    for (final d in declarations) d.canonical,
    for (final c in calls) c.canonical,
    if (withIdentifiers) 'ids|${identifiers.join(',')}',
  ];
}

/// The extractor that ships in `package:stagelatch`, in the shape of
/// `facts_model.dart`, so it can be compared with the parser (ADR-0017).
library;

// The shipped extractor is an implementation detail of the tool, and this
// throwaway package is the one place that measures it against the parser.
// ignore_for_file: implementation_imports
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/infrastructure/dart/syntactic_facts.dart'
    hide defaultTestFunctions;
import 'package:stagelatch_bench/facts_model.dart';

/// The facts of [source] from the shipped extractor, or null when it finds
/// the file not well formed and [requireWellFormed] is set. Identifiers are
/// not extracted yet.
FactsResult? factsByShipped(
  String source, {
  Set<String> testFunctions = defaultTestFunctions,
  bool requireWellFormed = false,
}) {
  final facts = SyntacticFacts(testFunctions: testFunctions)
      .extract(source, RepoPath('a.dart'));
  if (requireWellFormed && !facts.isWellFormed) return null;
  String at(Location l) => '${l.start.line}:${l.start.column}';
  return FactsResult(
    declarations: [
      for (final d in facts.annotatedDeclarations)
        DeclFact(
          name: d.name,
          annotations: d.annotations,
          tokenHash: d.tokenHash,
          line: d.location.start.line,
          column: d.location.start.column,
        ),
    ],
    calls: [
      for (final c in facts.testCalls)
        CallFact(
          function: c.function,
          description: c.description,
          groups: c.groups,
          line: c.location.start.line,
          column: c.location.start.column,
          solo: c.solo == null ? null : at(c.solo!),
          skip: c.skip == null ? null : at(c.skip!),
        ),
    ],
    identifiers: const [],
  );
}

/// Whether the shipped extractor finds [source] well formed.
bool shippedIsWellFormed(String source) =>
    const SyntacticFacts().extract(source, RepoPath('a.dart')).isWellFormed;

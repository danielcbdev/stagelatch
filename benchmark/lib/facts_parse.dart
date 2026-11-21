/// Annotated declarations and test calls through `package:analyzer`: the
/// reference candidate P of ADR-0017. It lives in `benchmark/` only; nothing
/// of stagelatch imports it.
library;

// The lexical token stream of the file, before the parser rewrites it (it
// splits `>>` in generics, for one), is what a "token hash" is defined on.
// The only public route to it is this `src` library, in this throwaway
// reference that nothing of the tool imports.
// ignore_for_file: implementation_imports
import 'package:_fe_analyzer_shared/src/scanner/scanner.dart' as scanner;
import 'package:_fe_analyzer_shared/src/scanner/token.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:stagelatch_bench/facts_model.dart';

/// The facts of [source], with `parseString` and the analyzer's scanner.
///
/// Returns null when the source has syntax errors and [requireValid] is
/// set, which is what ADR-0017 compares with the scanner's lexical check.
FactsResult? factsByParser(
  String source, {
  Set<String> testFunctions = defaultTestFunctions,
  bool requireValid = false,
}) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  if (requireValid && parsed.errors.isNotEmpty) return null;
  final unit = parsed.unit;
  final lines = parsed.lineInfo;
  final tokens = <Token>[];
  for (
    var t = scanner.scanString(source).tokens;
    t.type != TokenType.EOF;
    t = t.next!
  ) {
    tokens.add(t);
  }
  final ids = <String>{
    for (final t in tokens)
      if (t.isIdentifier || t is KeywordToken) t.lexeme,
  }.toList()..sort();
  return FactsResult(
    declarations: _declarations(unit, lines, tokens),
    calls: _calls(unit, lines, source, testFunctions),
    identifiers: ids,
  );
}

String _annotationName(Annotation a) => [
  a.name.toSource(),
  if (a.constructorName != null) a.constructorName!.name,
].join('.');

List<DeclFact> _declarations(
  CompilationUnit unit,
  LineInfo lines,
  List<Token> tokens,
) {
  final out = <DeclFact>[];

  void handle(AnnotatedNode node, String name) {
    final metadata = node.metadata;
    if (metadata.isEmpty) return;
    final names = [
      for (final a in metadata) _annotationName(a),
    ].where((n) => !ignoredAnnotations.contains(n)).toList()..sort();
    if (names.isEmpty) return;
    final start = metadata.first.offset;
    final end = node.end;
    final lexemes = [
      for (final t in tokens)
        if (t.offset >= start && t.offset < end) t.lexeme,
    ];
    final at = lines.getLocation(start);
    out.add(
      DeclFact(
        name: name,
        annotations: names,
        tokenHash: crypto.sha256
            .convert(lexemes.join(' ').codeUnits)
            .toString(),
        line: at.lineNumber,
        column: at.columnNumber,
      ),
    );
  }

  void members(String owner, List<ClassMember> list) {
    for (final m in list) {
      switch (m) {
        case MethodDeclaration():
          handle(m, '$owner.${m.name.lexeme}');
        case FieldDeclaration():
          handle(m, '$owner.${m.fields.variables.first.name.lexeme}');
        case ConstructorDeclaration():
          handle(m, '$owner.${m.name?.lexeme ?? 'new'}');
        default:
          break;
      }
    }
  }

  List<ClassMember> of(ClassBody body) => switch (body) {
    BlockClassBody(:final members) => members,
    _ => const [],
  };

  for (final d in unit.declarations) {
    switch (d) {
      case ClassDeclaration():
        final name = d.namePart.typeName.lexeme;
        handle(d, name);
        members(name, of(d.body));
      case MixinDeclaration():
        handle(d, d.name.lexeme);
        members(d.name.lexeme, of(d.body));
      case ExtensionDeclaration():
        final name = d.name?.lexeme ?? '<unnamed>';
        handle(d, name);
        members(name, of(d.body));
      case ExtensionTypeDeclaration():
        final name = d.namePart.typeName.lexeme;
        handle(d, name);
        members(name, of(d.body));
      case EnumDeclaration():
        final name = d.namePart.typeName.lexeme;
        handle(d, name);
        if (d.body case BlockEnumBody(:final constants, members: final list)) {
          for (final c in constants) {
            handle(c, '$name.${c.name.lexeme}');
          }
          members(name, list);
        }
      case FunctionDeclaration():
        handle(d, d.name.lexeme);
      case TopLevelVariableDeclaration():
        handle(d, d.variables.variables.first.name.lexeme);
      case ClassTypeAlias():
        handle(d, d.name.lexeme);
      case GenericTypeAlias():
        handle(d, d.name.lexeme);
      case FunctionTypeAlias():
        handle(d, d.name.lexeme);
      default:
        break;
    }
  }
  return out;
}

List<CallFact> _calls(
  CompilationUnit unit,
  LineInfo lines,
  String source,
  Set<String> functions,
) {
  String? librarySkip;
  for (final d in unit.directives) {
    if (d is LibraryDirective) {
      for (final a in d.metadata) {
        if (_annotationName(a) == 'Skip') {
          librarySkip ??= _at(lines, a.offset);
        }
      }
    }
  }
  final collector = _Calls(lines, source, functions, librarySkip);
  unit.accept(collector);
  return collector.calls;
}

String _at(LineInfo lines, int offset) {
  final l = lines.getLocation(offset);
  return '${l.lineNumber}:${l.columnNumber}';
}

final class _Calls extends RecursiveAstVisitor<void> {
  new(this._lines, this._source, this._functions, this._librarySkip);

  final LineInfo _lines;
  final String _source;
  final Set<String> _functions;
  final String? _librarySkip;
  final calls = <CallFact>[];
  final _groups = <String>[];
  String? _functionSkip;

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final top = node.parent is CompilationUnit;
    final saved = _functionSkip;
    if (top) {
      _functionSkip = null;
      for (final a in node.metadata) {
        if (_annotationName(a) == 'Skip') {
          _functionSkip ??= _at(_lines, a.offset);
        }
      }
    }
    super.visitFunctionDeclaration(node);
    if (top) _functionSkip = saved;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (node.target != null || node.isCascaded || !_functions.contains(name)) {
      super.visitMethodInvocation(node);
      return;
    }
    final args = node.argumentList.arguments;
    final positional = args.where((a) => a is! NamedArgument).toList();
    if (positional.isEmpty) {
      super.visitMethodInvocation(node);
      return;
    }
    final first = positional.first;
    final description = switch (first.argumentExpression) {
      StringLiteral(:final stringValue?) => stringValue,
      _ => _source.substring(first.offset, first.end),
    };
    String? solo;
    String? skip;
    for (final a in args) {
      if (a is! NamedArgument) continue;
      final label = a.name.lexeme;
      final e = a.argumentExpression;
      if (label == 'solo' && !(e is BooleanLiteral && !e.value)) {
        solo ??= _at(_lines, a.offset);
      }
      if (label == 'skip' &&
          !(e is BooleanLiteral && !e.value) &&
          e is! NullLiteral) {
        skip ??= _at(_lines, a.offset);
      }
    }
    final at = _lines.getLocation(node.methodName.offset);
    calls.add(
      CallFact(
        function: name,
        description: description,
        groups: [..._groups],
        line: at.lineNumber,
        column: at.columnNumber,
        solo: solo,
        skip: skip ?? _functionSkip ?? _librarySkip,
      ),
    );
    if (name == groupFunction) {
      _groups.add(description);
      super.visitMethodInvocation(node);
      _groups.removeLast();
    } else {
      super.visitMethodInvocation(node);
    }
  }
}

/// Whether `parseString` reports at least one syntax error for [source].
bool parsedHasErrors(String source) =>
    parseString(content: source, throwIfDiagnostics: false).errors.isNotEmpty;

/// The first syntax error `parseString` reports for [source], or null.
String? firstParseError(String source) {
  final errors = parseString(content: source, throwIfDiagnostics: false).errors;
  if (errors.isEmpty) return null;
  final e = errors.first;
  final code = e.diagnosticCode.lowerCaseName;
  return '$code at offset ${e.offset}: ${e.message}';
}

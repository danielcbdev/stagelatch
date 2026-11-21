/// What a source file tells a code generator (docs/specs/rules.md,
/// `codegen`).
library;

import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/location.dart';

/// Where two signatures first differ.
final class SignatureDifference {
  /// Creates a difference.
  const new({this.declaration, this.location});

  /// The name of the first differing declaration, or null when only the
  /// list of generated parts differs.
  final String? declaration;

  /// Where that declaration is in the newer file. Null for a declaration
  /// that was removed, for a new file, and when only the generated parts
  /// differ: the caller falls back to the `part` directive.
  final Location? location;
}

/// The part of a Dart file that decides what a code generator writes: the
/// generated parts it declares, and every annotated declaration with its
/// annotation names and token hash.
///
/// Two signatures are equal when a generator would produce the same output
/// for both. Whitespace and comments are not tokens, so they are never a
/// difference.
final class CodegenSignature {
  const new _(this.generatedParts, this.partDirectives, this._declarations);

  /// Reads the signature of a file with these [facts]. A part is generated
  /// when its URI ends with one of [suffixes]; a URI with a scheme
  /// (`package:`) is not a file of this repository and is left out.
  factory of(DartFileFacts facts, List<String> suffixes) {
    final parts = [
      for (final directive in facts.directives)
        if (directive.kind == DirectiveKind.part &&
            !directive.uri.contains(':') &&
            suffixes.any(directive.uri.endsWith))
          directive,
    ];
    return CodegenSignature._(
      List.unmodifiable([for (final part in parts) part.uri]),
      List.unmodifiable(parts),
      List.unmodifiable(facts.annotatedDeclarations),
    );
  }

  /// The URIs of the generated parts, as written, in source order.
  final List<String> generatedParts;

  /// The `part` directives of [generatedParts], with their locations.
  final List<Directive> partDirectives;

  final List<AnnotatedDeclaration> _declarations;

  /// Where this signature first differs from [base], or null when they are
  /// equal. A null [base] is a file that is new, which always differs.
  ///
  /// Declarations are matched by name and occurrence, so a getter and a
  /// setter with one name are compared pairwise. A declaration that exists
  /// here and not in [base], or changed, is named with its location; one
  /// that [base] had and this does not is named without one. Failing both,
  /// a different list of generated parts is a difference with no
  /// declaration.
  SignatureDifference? firstDifference(CodegenSignature? base) {
    if (base == null) {
      return SignatureDifference(
        declaration: _declarations.isEmpty ? null : _declarations.first.name,
      );
    }
    final before = _byOccurrence(base._declarations);
    final now = _byOccurrence(_declarations);
    for (final MapEntry(:key, :value) in now.entries) {
      final old = before[key];
      if (old == null ||
          old.tokenHash != value.tokenHash ||
          !_sameStrings(old.annotations, value.annotations)) {
        return SignatureDifference(
          declaration: value.name,
          location: value.location,
        );
      }
    }
    for (final MapEntry(:key, :value) in before.entries) {
      if (!now.containsKey(key)) {
        return SignatureDifference(declaration: value.name);
      }
    }
    if (!_sameStrings(generatedParts, base.generatedParts)) {
      return const SignatureDifference();
    }
    return null;
  }

  /// The declarations keyed by name and how many with that name came
  /// before, in order.
  static Map<String, AnnotatedDeclaration> _byOccurrence(
    List<AnnotatedDeclaration> declarations,
  ) {
    final seen = <String, int>{};
    final result = <String, AnnotatedDeclaration>{};
    for (final declaration in declarations) {
      final occurrence = seen.update(
        declaration.name,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      result['${declaration.name}#$occurrence'] = declaration;
    }
    return result;
  }

  static bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

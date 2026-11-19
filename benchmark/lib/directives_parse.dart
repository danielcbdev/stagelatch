/// Directive URIs through `package:analyzer`'s parser.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Returns the URIs of the `import`, `export`, `part` and `part of`
/// directives of [source], in source order.
///
/// A conditional import or export contributes its default URI followed by
/// the URI of each configuration (`specs/dart-toolchain.md` section 3).
/// `part of` with a library name has no URI and contributes nothing.
List<String> directivesByParser(String source) {
  // throwIfDiagnostics: false, a file with syntax errors still yields the
  // directives that parsed; the scanner below behaves the same way.
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  return [
    for (final directive in unit.directives)
      ...switch (directive) {
        NamespaceDirective(:final uri, :final configurations) => [
          ?uri.stringValue,
          for (final c in configurations) ?c.uri.stringValue,
        ],
        PartDirective(:final uri) => [?uri.stringValue],
        PartOfDirective(:final uri) => [?uri?.stringValue],
        _ => const <String>[],
      },
  ];
}

/// The rules of the `codegen` check (docs/specs/rules.md).
library;

import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The id of the check, and the first part of its rule id.
const String codegenCheckId = 'codegen';

/// A source file whose annotated declarations changed while the generated
/// part that depends on them did not, or whose generated part is missing.
const RuleId staleRule = RuleId(codegenCheckId, 'stale');

/// What the check declares about its rules.
const List<RuleDescriptor> codegenRuleDescriptors = [
  RuleDescriptor(
    id: staleRule,
    defaultSeverity: Severity.error,
    summary: 'A generated file was not updated with its source.',
  ),
];

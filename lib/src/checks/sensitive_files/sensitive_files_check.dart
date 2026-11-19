/// The `sensitive-files` check (docs/specs/rules.md, `sensitive-files`).
library;

import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/documents.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';

/// The id of the check.
const String sensitiveFilesCheckId = 'sensitive-files';

/// Keystores, signing keys and their property files.
const RuleId signingRule = RuleId(sensitiveFilesCheckId, 'signing');

/// Environment files and service account keys.
const RuleId credentialsRule = RuleId(sensitiveFilesCheckId, 'credentials');

const String _signingMessage = 'Signing material must not be committed.';
const String _credentialsMessage = 'Credentials file must not be committed.';

/// The largest JSON file read to look for a service account: 1 MiB.
const int _maxJsonBytes = 1024 * 1024;

const Set<String> _signingExtensions = {
  '.jks',
  '.keystore',
  '.p8',
  '.p12',
  '.pfx',
};

const Set<String> _envExamples = {
  '.env.example',
  '.env.sample',
  '.env.template',
};

/// Reports files that hold secrets, judged by path and, for JSON, by
/// structure. A finding names the path and the rule, never content
/// (security S5): this is not secret scanning.
final class SensitiveFilesCheck implements Check {
  /// Creates the check.
  const new();

  @override
  String get id => sensitiveFilesCheckId;

  @override
  CheckPhase get phase => CheckPhase.verify;

  @override
  List<RuleDescriptor> get rules => const [
    RuleDescriptor(
      id: signingRule,
      defaultSeverity: Severity.error,
      summary: 'A keystore, signing key or key.properties is committed.',
    ),
    RuleDescriptor(
      id: credentialsRule,
      defaultSeverity: Severity.error,
      summary: 'An .env file or a service account key is committed.',
    ),
  ];

  @override
  bool get hasDynamicRules => false;

  @override
  Future<CheckResult> run(CheckContext context) async {
    final signing = context.isEnabled(signingRule);
    final credentials = context.isEnabled(credentialsRule);
    final findings = <Finding>[];
    for (final change in context.changes.present) {
      final path = change.path;
      if (signing && _isSigning(path)) {
        findings.add(_finding(signingRule, path, _signingMessage));
      } else if (credentials &&
          (_isEnvFile(path) || await _isServiceAccount(context, path))) {
        findings.add(_finding(credentialsRule, path, _credentialsMessage));
      }
    }
    return CheckResult(findings: findings);
  }

  static bool _isSigning(RepoPath path) =>
      path.basename == 'key.properties' ||
      _signingExtensions.contains(path.extension.toLowerCase());

  static bool _isEnvFile(RepoPath path) {
    final name = path.basename;
    if (_envExamples.contains(name)) return false;
    return name == '.env' || name.startsWith('.env.');
  }

  /// Whether [path] is a JSON file of at most 1 MiB whose top-level object
  /// has `"type": "service_account"`. Larger or invalid JSON is not read.
  static Future<bool> _isServiceAccount(
    CheckContext context,
    RepoPath path,
  ) async {
    if (path.extension.toLowerCase() != '.json') return false;
    final entry = await context.snapshot.entry(path);
    if (entry == null || !entry.mode.isFile) return false;
    final size = await context.snapshot.size(path);
    if (size == null || size > _maxJsonBytes) return false;
    final document = await context.documents.json(context.snapshot, path);
    return switch (document) {
      DocumentParsed(root: LocatedMap(:final entries)) =>
        switch (entries['type']?.value) {
          LocatedScalar(value: 'service_account') => true,
          _ => false,
        },
      _ => false,
    };
  }

  static Finding _finding(RuleId rule, RepoPath path, String message) =>
      Finding(
        rule: rule,
        severity: Severity.error,
        message: message,
        location: Location.wholeFile(path),
      );
}

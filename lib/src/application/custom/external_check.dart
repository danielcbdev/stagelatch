/// Verify-phase check that forwards to a custom-check child
/// (docs/specs/custom-checks.md, ADR-0019).
library;

import 'dart:async';

import 'package:stagelatch/src/application/custom/protocol.dart';
import 'package:stagelatch/src/application/custom/protocol_codec.dart';
import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/application/ports/check_process.dart';
import 'package:stagelatch/src/application/text/sanitize.dart';
import 'package:stagelatch/src/domain/change_set.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/snapshot.dart';

/// A verify-phase [Check] that runs a child over protocol 1.
final class ExternalCheck implements Check {
  /// Creates the check.
  ///
  /// [command] is the argument list from config (possibly still containing
  /// bare `dart`/`flutter` or PATH names; the factory resolves them).
  /// [sourceClosure] must be non-empty. [all] mirrors `--all`.
  /// [workingDirectory] is the repository root.
  new({
    required this.id,
    required List<String> command,
    required this._factory,
    required this.timeout,
    required Set<RepoPath> sourceClosure,
    required this.workingDirectory,
    this.settings = const {},
    this.all = false,
  }) : _command = List.unmodifiable(command),
       _sourceClosure = Set.unmodifiable(sourceClosure);

  @override
  final String id;

  final List<String> _command;
  final CheckProcessFactory _factory;

  /// Per-check hang limit (default 60s in config).
  final Duration timeout;

  final Set<RepoPath> _sourceClosure;

  /// Repository root passed to [CheckProcessFactory.start].
  final String workingDirectory;

  /// Extra keys from `custom_checks.<id>` (excluding reserved ones).
  final Map<String, Object?> settings;

  /// Whether `--all` was passed for this pipeline run.
  final bool all;

  @override
  CheckPhase get phase => CheckPhase.verify;

  @override
  List<RuleDescriptor> get rules => const [];

  @override
  bool get hasDynamicRules => true;

  @override
  Future<CheckResult> run(CheckContext context) async {
    await _ensureSourcesInSnapshot(context.snapshot);

    final before = await context.divergentAmong(_sourceClosure);
    if (before.isNotEmpty) {
      throw UsageException(_divergeMessage(context.entry, _firstPath(before)));
    }

    CheckProcess? process;
    try {
      try {
        process = await _factory.start(
          _command,
          workingDirectory: workingDirectory,
        );
      } on InternalException catch (error) {
        throw InternalException(
          'custom check "$id": ${error.message}',
          where: 'check "$id"',
          cause: error,
        );
      } on Object catch (error) {
        throw InternalException(
          'custom check "$id": cannot start: $error',
          where: 'check "$id"',
          cause: error,
        );
      }

      final findings = await _speak(process, context).timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('custom check "$id" timed out');
        },
      );

      final after = await context.divergentAmong(_sourceClosure);
      if (after.isNotEmpty) {
        throw UsageException(_divergeMessage(context.entry, _firstPath(after)));
      }

      return CheckResult(findings: findings);
    } on TimeoutException {
      throw InternalException(
        'custom check "$id": timed out after ${_formatTimeout(timeout)}.',
        where: 'check "$id"',
      );
    } on ProtocolException catch (error) {
      throw InternalException(
        _protocolMessage(error),
        where: 'check "$id"',
        cause: error,
      );
    } on UsageException {
      rethrow;
    } on InternalException {
      rethrow;
    } finally {
      if (process != null) await process.kill();
    }
  }

  Future<void> _ensureSourcesInSnapshot(SnapshotFiles snapshot) async {
    for (final source in _sourceClosure) {
      final entry = await snapshot.entry(source);
      if (entry == null || !entry.mode.isFile) {
        throw InternalException(
          'custom check "$id": source "${source.value}" is missing '
          'from the snapshot.',
          where: 'check "$id"',
        );
      }
    }
  }

  Future<List<Finding>> _speak(
    CheckProcess process,
    CheckContext context,
  ) async {
    final findings = <Finding>[];
    final declared = <RuleId, RuleDescriptor>{};
    var sawReady = false;
    var sawDone = false;
    final pendingReads = <int>{};

    process.send(
      encodeToCheck(
        InitMessage(
          protocol: customCheckProtocol,
          entry: context.entry,
          settings: settings,
        ),
      ),
    );

    await for (final line in process.lines) {
      final message = decodeFromCheck(line);
      switch (message) {
        case ReadyMessage(:final rules):
          if (sawReady) {
            throw const ProtocolException('unexpected second ready');
          }
          sawReady = true;
          for (final rule in rules) {
            if (rule.id.check != id) {
              throw ProtocolException(
                'rule "${rule.id}" must use check id "$id"',
              );
            }
            declared[rule.id] = rule;
          }
          process.send(
            encodeToCheck(
              RunMessage(
                changes: [
                  for (final change in context.changes.changes)
                    if (change.kind != ChangeKind.typeChanged) change,
                ],
                all: all,
              ),
            ),
          );
        case ReadMessage(:final id, :final path, :final side):
          if (!sawReady) {
            throw const ProtocolException('read before ready');
          }
          if (sawDone) {
            throw const ProtocolException('read after done');
          }
          if (!pendingReads.add(id)) {
            throw ProtocolException('duplicate read id $id');
          }
          final text = await _readSide(context, path, side);
          pendingReads.remove(id);
          process.send(encodeToCheck(ContentMessage(id: id, text: text)));
        case FindingMessage(
          :final rule,
          :final path,
          :final line,
          :final column,
          :final message,
        ):
          if (!sawReady) {
            throw const ProtocolException('finding before ready');
          }
          if (sawDone) {
            throw const ProtocolException('finding after done');
          }
          if (rule.check != id) {
            throw ProtocolException(
              'finding rule "$rule" must use check id "$id"',
            );
          }
          final descriptor = declared[rule];
          if (descriptor == null) {
            throw ProtocolException('undeclared rule "$rule"');
          }
          if (findings.length >= maxFindingsPerCustomCheck) {
            throw const ProtocolException(
              'exceeded $maxFindingsPerCustomCheck findings',
            );
          }
          findings.add(
            Finding(
              rule: rule,
              severity: descriptor.defaultSeverity,
              message: message,
              location: Location(
                path,
                Position(line, column),
                Position(line, column),
              ),
            ),
          );
        case DoneMessage():
          if (!sawReady) {
            throw const ProtocolException('done before ready');
          }
          sawDone = true;
      }
      if (sawDone) break;
    }

    await process.closeStdin();
    final code = await process.exitCode;
    final stderr = await process.standardError;

    if (!sawDone) {
      if (code != 0) {
        final excerpt = _stderrExcerpt(stderr);
        throw InternalException(
          'custom check "$id": exited with code $code.'
          '${excerpt == null ? '' : ' $excerpt'}',
          where: 'check "$id"',
        );
      }
      throw InternalException(
        'custom check "$id": exited before done.',
        where: 'check "$id"',
      );
    }

    return findings;
  }

  Future<String?> _readSide(
    CheckContext context,
    RepoPath path,
    String side,
  ) async {
    final files = switch (side) {
      'snapshot' => context.snapshot,
      'base' => context.base,
      _ => null,
    };
    if (files == null) return null;
    return await files.readText(path);
  }

  String _protocolMessage(ProtocolException error) {
    final reason = error.line == null
        ? error.reason
        : '${error.reason}: ${error.line}';
    return 'custom check "$id": protocol error: $reason';
  }

  String _divergeMessage(EntryKind entry, RepoPath path) {
    final resolve = switch (entry) {
      EntryKind.preCommit =>
        'Stage the check source changes, or pass --no-custom-checks.',
      EntryKind.prePush =>
        'Commit the check source changes or check out the pushed revision, '
            'or pass --no-custom-checks.',
      EntryKind.ci =>
        'Commit or discard local changes so the working tree matches the '
            'snapshot, or pass --no-custom-checks.',
    };
    return 'custom check "$id": source diverges from the snapshot at '
        '${path.value}. $resolve';
  }

  static RepoPath _firstPath(Set<RepoPath> paths) {
    final sorted = paths.toList()..sort();
    return sorted.first;
  }

  static String? _stderrExcerpt(String stderr) {
    final trimmed = stderr.trim();
    if (trimmed.isEmpty) return null;
    final sanitized = sanitizeForTerminal(trimmed);
    return sanitized.length <= 200 ? sanitized : sanitized.substring(0, 200);
  }

  static String _formatTimeout(Duration duration) {
    final milliseconds = duration.inMilliseconds;
    if (milliseconds % 1000 == 0) return '${milliseconds ~/ 1000}s';
    return '${milliseconds}ms';
  }
}

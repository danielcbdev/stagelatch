/// The three ways a run can be started (ADR-0007).
library;

import 'package:stagelatch/src/domain/check.dart';

/// What started a run, with the input that entry point supplies.
///
/// Every entry point is served by the same pipeline (ADR-0005); the only
/// thing that differs is which snapshot and changeset it resolves to.
sealed class EntryPoint {
  const new();

  /// The kind of this entry point, as checks see it.
  EntryKind get kind;
}

/// `stagelatch run pre-commit`: judges the index against `HEAD`.
final class PreCommitEntry extends EntryPoint {
  /// Creates the entry point.
  const new();

  @override
  EntryKind get kind => EntryKind.preCommit;
}

/// `stagelatch run pre-push`: judges each pushed commit.
final class PrePushEntry extends EntryPoint {
  /// Creates the entry point for a push to [remote] of [refs].
  const new({required this.remote, required this.refs});

  /// The name of the remote being pushed to, as git passes it to the hook.
  final String remote;

  /// One element per line git writes to the hook's standard input.
  final List<PushedRef> refs;

  @override
  EntryKind get kind => EntryKind.prePush;
}

/// `stagelatch ci`: judges the head of a pull request against its base.
final class CiEntry extends EntryPoint {
  /// Creates the entry point for the range from [baseRef] to [headRef].
  const new({required this.baseRef, this.headRef = 'HEAD'});

  /// The ref the change is to be merged into.
  final String baseRef;

  /// The ref being judged.
  final String headRef;

  @override
  EntryKind get kind => EntryKind.ci;
}

/// One line of a pre-push hook's standard input:
/// `<local ref> <local sha> <remote ref> <remote sha>`.
final class PushedRef {
  /// Creates a pushed ref.
  const new({
    required this.localRef,
    required this.localSha,
    required this.remoteRef,
    required this.remoteSha,
  });

  /// The local ref being pushed, for example `refs/heads/feature`.
  final String localRef;

  /// The commit being pushed; all zeros when the remote ref is deleted.
  final String localSha;

  /// The ref on the remote that will be updated.
  final String remoteRef;

  /// What the remote ref points at now; all zeros when it does not exist.
  final String remoteSha;
}

import 'package:stagelatch/src/application/entry_point.dart';
import 'package:stagelatch/src/application/ports/git_repository.dart';
import 'package:stagelatch/src/domain/check.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:test/test.dart';

void main() {
  group('EntryPoint', () {
    test('each entry point knows its kind', () {
      const push = PrePushEntry(remote: 'origin', refs: []);
      const ci = CiEntry(baseRef: 'origin/main');

      expect(const PreCommitEntry().kind, EntryKind.preCommit);
      expect(push.kind, EntryKind.prePush);
      expect(ci.kind, EntryKind.ci);
    });

    test('ci judges HEAD unless told otherwise', () {
      expect(const CiEntry(baseRef: 'origin/main').headRef, 'HEAD');
      expect(const CiEntry(baseRef: 'a', headRef: 'b').headRef, 'b');
    });

    test('a pushed ref carries the four fields git supplies', () {
      const ref = PushedRef(
        localRef: 'refs/heads/feature',
        localSha: 'aaa',
        remoteRef: 'refs/heads/feature',
        remoteSha: 'bbb',
      );
      const push = PrePushEntry(remote: 'origin', refs: [ref]);

      expect(push.remote, 'origin');
      expect(push.refs.single.localRef, 'refs/heads/feature');
      expect(push.refs.single.localSha, 'aaa');
      expect(push.refs.single.remoteRef, 'refs/heads/feature');
      expect(push.refs.single.remoteSha, 'bbb');
    });
  });

  group('SnapshotRef', () {
    test('the index equals the index', () {
      expect(const IndexSnapshot(), const IndexSnapshot());
      expect(const IndexSnapshot().hashCode, const IndexSnapshot().hashCode);
    });

    test('a commit snapshot is identified by its sha', () {
      expect(const CommitSnapshot('abc'), const CommitSnapshot('abc'));
      expect(
        const CommitSnapshot('abc').hashCode,
        const CommitSnapshot('abc').hashCode,
      );
      expect(const CommitSnapshot('abc'), isNot(const CommitSnapshot('def')));
      expect(const CommitSnapshot('abc'), isNot(const IndexSnapshot()));
    });

    test('prints as index or as its sha', () {
      expect(const IndexSnapshot().toString(), 'index');
      expect(const CommitSnapshot('abc').toString(), 'abc');
    });
  });

  group('AppliedFix', () {
    test('is equal when rule, path and worktree flag are equal', () {
      AppliedFix fix({bool worktreeUpdated = true}) => AppliedFix(
        rule: const RuleId('format', 'unformatted'),
        path: RepoPath('lib/a.dart'),
        worktreeUpdated: worktreeUpdated,
      );

      expect(fix(), fix());
      expect(fix().hashCode, fix().hashCode);
      expect(fix(), isNot(fix(worktreeUpdated: false)));
    });
  });
}

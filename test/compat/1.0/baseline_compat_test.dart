import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:stagelatch/src/application/baseline/baseline_codec.dart';
import 'package:stagelatch/src/application/baseline/fingerprint.dart';
import 'package:stagelatch/src/domain/finding.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:stagelatch/src/domain/repo_path.dart';
import 'package:stagelatch/src/domain/rule_id.dart';
import 'package:stagelatch/src/domain/severity.dart';
import 'package:test/test.dart';

import '../../support/fake_snapshot_files.dart';
import 'fixtures_path.dart';

void main() {
  test('frozen baseline.json round-trips through the codec', () {
    final raw = readCompatFixture('baseline.json');
    final baseline = decodeBaseline(raw);
    final reencoded = encodeBaseline(baseline);
    final again = encodeBaseline(decodeBaseline(reencoded));

    expect(again, reencoded);
    expect((jsonDecode(reencoded) as Map<String, Object?>)['version'], 1);
    expect(
      (jsonDecode(reencoded) as Map<String, Object?>)['version'],
      baselineVersion,
    );
    expect(baseline.entries, hasLength(2));
    expect(baseline.entries.map((e) => e.rule.toString()).toSet(), {
      'format/unformatted',
      'pubspec/path-dependency',
    });
  });

  test('fingerprint algorithm is rule + path + normalized snippet', () async {
    final finding = Finding(
      rule: RuleId.parse('pubspec/path-dependency'),
      severity: Severity.error,
      message: 'x',
      location: Location(
        RepoPath('pubspec.yaml'),
        const Position(1, 1),
        const Position(1, 1),
      ),
    );
    final snapshot = FakeSnapshotFiles({'pubspec.yaml': '  name:   demo\n'});

    final fingerprint = await fingerprintOf(finding, snapshot);
    final expected = sha256
        .convert(
          utf8.encode(
            'pubspec/path-dependency\npubspec.yaml\n'
            '${normalizeSnippet(['  name:   demo'])}',
          ),
        )
        .toString();

    expect(fingerprint, expected);
    expect(fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
  });
}

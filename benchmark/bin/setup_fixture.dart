/// Creates the `old_sdk` fixture: a small Flutter package that resolves
/// on the previous stable Flutter minor, for the parity check of plan 00,
/// Task 4 step 4 (the corpus itself needs Dart ^3.13).
///
/// Usage, from the stagelatch checkout:
/// `dart run benchmark/bin/setup_fixture.dart`. Running it twice is a
/// no-op. The files are generated here rather than kept as a template, so
/// the root `dart analyze` never sees a Flutter package it cannot resolve.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/corpus.dart';
import 'package:stagelatch_bench/proc.dart';
import 'package:stagelatch_bench/workspace.dart';

/// Files that import the hub: s10 needs one file with 100+ importers.
const _tileCount = 110;

Future<void> main() async {
  final ws = BenchWorkspace.find(corpus: 'old_sdk');
  final corpus = Corpus.load(ws);
  final dir = ws.corpusDir;

  if (await _head(dir) != corpus.sha) {
    if (Directory(dir).existsSync()) Directory(dir).deleteSync(recursive: true);
    _files().forEach((path, content) {
      File(p.join(dir, path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    });
    // A fixed identity and date make the commit, and so the SHA pinned in
    // corpus.yaml, the same on every machine.
    const who = 'stagelatch-bench';
    const when = '2026-11-18T00:00:00Z';
    final env = {
      'GIT_AUTHOR_NAME': who,
      'GIT_AUTHOR_EMAIL': '$who@invalid',
      'GIT_AUTHOR_DATE': when,
      'GIT_COMMITTER_NAME': who,
      'GIT_COMMITTER_EMAIL': '$who@invalid',
      'GIT_COMMITTER_DATE': when,
    };
    await run('git', ['init', '-q', '-b', 'main'], workingDirectory: dir);
    await run('git', ['add', '-A'], workingDirectory: dir);
    // --no-gpg-sign: a signature would change the commit object.
    await run(
      'git',
      [
        '-c',
        'commit.gpgsign=false',
        'commit',
        '-q',
        '--no-verify',
        '-m',
        'fixture',
      ],
      workingDirectory: dir,
      environment: env,
    );
    final head = await _head(dir);
    if (head != corpus.sha) {
      stderr.writeln(
        'Fixture commit is $head; corpus.yaml says ${corpus.sha}.',
      );
      exitCode = 1;
      return;
    }
  }

  final flutter = p.join(Corpus.flutterSdk(corpus.flutter), 'bin', 'flutter');
  if (!File(flutter).existsSync()) {
    stderr.writeln('Run: fvm install ${corpus.flutter}');
    exitCode = 1;
    return;
  }
  final marker = File(p.join(dir, '.dart_tool', 'stagelatch_bench_flutter'));
  if (marker.existsSync() && marker.readAsStringSync() == corpus.flutter) {
    stdout.writeln(
      'Fixture ready at ${corpus.sha} (Flutter ${corpus.flutter}).',
    );
    return;
  }
  await run(flutter, ['pub', 'get'], workingDirectory: dir);
  marker.writeAsStringSync(corpus.flutter);
  stdout.writeln('Fixture ready at ${corpus.sha} (Flutter ${corpus.flutter}).');
}

Future<String> _head(String dir) async {
  if (!Directory(p.join(dir, '.git')).existsSync()) return '';
  try {
    final out = await run('git', [
      'rev-parse',
      '--verify',
      '-q',
      'HEAD',
    ], workingDirectory: dir);
    return out.trim();
  } on ProcessException {
    return '';
  }
}

Map<String, String> _files() => {
  '.gitignore': '.dart_tool/\npubspec.lock\nbuild/\n',
  'pubspec.yaml': '''
name: fixture_app
publish_to: none
version: 1.0.0

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_lints: any
''',
  'analysis_options.yaml': '''
include: package:flutter_lints/flutter.yaml

analyzer:
  errors:
    dead_code: warning

linter:
  rules:
    - directives_ordering
    - prefer_const_constructors

formatter:
  page_width: 100
''',
  'lib/main.dart': '''
import 'package:fixture_app/badges/badge_sheet.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: BadgeSheet(badgeId: 'creator')));
''',
  'lib/core/hub.dart': '''
/// Where a tile comes from. Imported by every tile.
enum Tone { calm, bright, muted }

extension ToneX on Tone {
  String get wireValue => switch (this) {
    Tone.calm => 'calm',
    Tone.bright => 'bright',
    Tone.muted => 'muted',
  };
}
''',
  for (var i = 0; i < _tileCount; i++)
    'lib/tiles/tile_${'$i'.padLeft(3, '0')}.dart':
        '''
import 'package:fixture_app/core/hub.dart';
import 'package:flutter/widgets.dart';

class Tile$i extends StatelessWidget {
  const Tile$i({super.key, this.tone = Tone.calm});

  final Tone tone;

  @override
  Widget build(BuildContext context) => Text('$i \${tone.wireValue}');
}
''',
  'lib/badges/badge_repository.dart': '''
class EarnedBadge {
  const EarnedBadge({required this.id, required this.coins});

  final String id;
  final int coins;
}

abstract class BadgeRepository {
  /// Asks the server to award any badges now earned.
  Future<List<EarnedBadge>> check();
}
''',
  'lib/badges/badges_bloc.dart': '''
import 'package:fixture_app/badges/badge_repository.dart';
import 'package:flutter/foundation.dart';

enum BadgesStatus { initial, loading, success, failure }

class BadgesBloc extends ValueNotifier<BadgesStatus> {
  BadgesBloc(this._repository) : super(BadgesStatus.initial);

  final BadgeRepository _repository;

  Future<void> load() async {
    value = BadgesStatus.loading;
    final List<EarnedBadge> badges = await _repository.check();
    value = badges.isEmpty ? BadgesStatus.failure : BadgesStatus.success;
  }
}
''',
  'lib/badges/badge_catalog.dart': '''
import 'package:flutter/material.dart';
import 'package:fixture_app/core/hub.dart';

class BadgeInfo {
  const BadgeInfo({required this.id, required this.icon, this.tone = Tone.calm});

  final String id;
  final IconData icon;
  final Tone tone;
}

const List<BadgeInfo> badgeCatalog = <BadgeInfo>[
  BadgeInfo(id: 'creator', icon: Icons.brush_rounded),
  BadgeInfo(id: 'collector', icon: Icons.favorite_rounded, tone: Tone.bright),
];

/// The catalog entry for [id], or null for a badge this version does not know.
BadgeInfo? badgeInfo(String id) {
  for (final BadgeInfo info in badgeCatalog) {
    if (info.id == id) return info;
  }
  return null;
}
''',
  'lib/badges/badge_sheet.dart': '''
import 'package:fixture_app/badges/badge_catalog.dart';
import 'package:fixture_app/badges/badge_repository.dart';
import 'package:flutter/material.dart';

class BadgeSheet extends StatelessWidget {
  const BadgeSheet({super.key, required this.badgeId, this.earned});

  final String badgeId;
  final EarnedBadge? earned;

  @override
  Widget build(BuildContext context) {
    final BadgeInfo? info = badgeInfo(badgeId);
    final bool small = MediaQuery.sizeOf(context).height < 700;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(info?.icon ?? Icons.help_outline, size: small ? 48 : 96),
        const SizedBox(height: 8),
        Text(
          info?.id ?? 'unknown',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );
  }
}
''',
};

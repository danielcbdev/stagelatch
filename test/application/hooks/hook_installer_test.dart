import 'package:stagelatch/src/application/hooks/hook_action.dart';
import 'package:stagelatch/src/application/hooks/hook_installer.dart';
import 'package:stagelatch/src/application/hooks/hook_name.dart';
import 'package:stagelatch/src/application/hooks/hook_script.dart';
import 'package:test/test.dart';

import '../../support/fake_hook_store.dart';

void main() {
  late FakeHookStore store;
  late HookInstaller installer;

  setUp(() {
    store = FakeHookStore();
    installer = HookInstaller(store);
  });

  test('install writes a script where none exists', () async {
    final actions = await installer.install({HookName.preCommit}, force: false);

    expect(actions, [isA<HookInstalled>()]);
    expect(actions.single.path, '/hooks/pre-commit');
    expect(
      store.files[HookName.preCommit],
      renderHookScript(HookName.preCommit),
    );
  });

  test('install leaves an identical managed hook untouched', () async {
    store.files[HookName.preCommit] = renderHookScript(HookName.preCommit);

    final actions = await installer.install({HookName.preCommit}, force: false);

    expect(actions, [isA<HookUpToDate>()]);
  });

  test('install overwrites a managed hook whose text differs', () async {
    store.files[HookName.preCommit] =
        '#!/bin/sh\n# stagelatch:managed\necho old\n';

    final actions = await installer.install({HookName.preCommit}, force: false);

    expect(actions, [isA<HookUpdated>()]);
    expect(store.backups, isEmpty);
    expect(
      store.files[HookName.preCommit],
      renderHookScript(HookName.preCommit),
    );
  });

  test('install refuses an unmanaged hook and leaves it untouched', () async {
    store.files[HookName.preCommit] = '#!/bin/sh\nhusky\n';

    final actions = await installer.install({HookName.preCommit}, force: false);

    expect(actions, [isA<HookRefused>()]);
    expect(actions.single.hook, HookName.preCommit);
    expect(store.files[HookName.preCommit], '#!/bin/sh\nhusky\n');
  });

  test('force backs up an unmanaged hook before replacing it', () async {
    store.files[HookName.preCommit] = '#!/bin/sh\nhusky\n';

    final actions = await installer.install({HookName.preCommit}, force: true);

    expect(actions, [isA<HookReplaced>()]);
    final replaced = actions.single as HookReplaced;
    expect(replaced.backup, 'pre-commit.stagelatch-backup');
    expect(store.backups[replaced.backup], '#!/bin/sh\nhusky\n');
    expect(
      store.files[HookName.preCommit],
      renderHookScript(HookName.preCommit),
    );
  });

  test('a second backup gets a numeric suffix', () async {
    store.files[HookName.preCommit] = 'first\n';
    expect(
      await store.backup(HookName.preCommit),
      'pre-commit.stagelatch-backup',
    );

    store.files[HookName.preCommit] = 'second\n';
    expect(
      await store.backup(HookName.preCommit),
      'pre-commit.stagelatch-backup.1',
    );
  });

  test(
    'uninstall removes a managed hook and restores the newest backup',
    () async {
      store.files[HookName.preCommit] = 'older\n';
      await store.backup(HookName.preCommit);
      store.files[HookName.preCommit] = 'newer\n';
      await store.backup(HookName.preCommit);
      store.files[HookName.preCommit] = renderHookScript(HookName.preCommit);

      final actions = await installer.uninstall();
      final restored = actions[1] as HookRestored;

      expect(actions[0], isA<HookRemoved>());
      expect(restored.backup, 'pre-commit.stagelatch-backup.1');
      expect(actions[2], isA<HookNotFound>());
      expect(store.files[HookName.preCommit], 'newer\n');
    },
  );

  test('uninstall never touches an unmanaged hook', () async {
    store.files[HookName.preCommit] = '#!/bin/sh\nhusky\n';

    final actions = await installer.uninstall();

    expect(actions, [isA<HookNotFound>(), isA<HookNotFound>()]);
    expect(store.files[HookName.preCommit], '#!/bin/sh\nhusky\n');
  });

  test('install reports the requested hooks in enum order', () async {
    final actions = await installer.install({
      HookName.prePush,
      HookName.preCommit,
    }, force: false);

    expect(actions.map((action) => action.hook), [
      HookName.preCommit,
      HookName.prePush,
    ]);
  });
}

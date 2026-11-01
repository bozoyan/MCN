// 职责: 验证小说工作区状态按小说使用单个 app_states key 恢复与串行持久化。
// 关联文件:
//   lib/shared/providers/novel_workspace_state_provider.dart
//   lib/shared/models/novel_workspace_state.dart
//   lib/shared/database/app_database.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/testing.md

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/novel_workspace_state_provider.dart';

void main() {
  test('restores selection and expanded nodes from one novel key', () async {
    final database = AppDatabase.forTest(NativeDatabase.memory());
    const novelId = 'novel_1';
    await database.appStateDao.set(
      key: novelWorkspaceAppStateKey(novelId),
      value: jsonEncode(<String, dynamic>{
        'version': 1,
        'selection': <String, dynamic>{
          'section': 'chapters',
          'itemId': 'chapter_2',
        },
        'expandedNodes': <String, dynamic>{
          'chapters': <String>['volume_1'],
          'materials': <String>['folder_1'],
        },
      }),
    );
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    final provider = novelWorkspaceStateControllerProvider(novelId);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await database.close();
    });

    final notifier = container.read(provider.notifier);
    await notifier.ready;
    final restored = container.read(provider);

    expect(restored.isHydrated, isTrue);
    expect(
      restored.selection,
      const WorkspaceSelection(
        section: NovelWorkspaceSection.chapters,
        itemId: 'chapter_2',
      ),
    );
    expect(
      restored.expandedNodeIdsFor(NovelWorkspaceSection.chapters),
      <String>{'volume_1'},
    );
    expect(
      restored.expandedNodeIdsFor(NovelWorkspaceSection.materials),
      <String>{'folder_1'},
    );
  });

  test('serializes rapid updates and never persists creation state', () async {
    final database = AppDatabase.forTest(NativeDatabase.memory());
    const novelId = 'novel_2';
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    final provider = novelWorkspaceStateControllerProvider(novelId);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await database.close();
    });

    final notifier = container.read(provider.notifier);
    await notifier.ready;
    notifier.value = const WorkspaceSelection(
      section: NovelWorkspaceSection.chapters,
      itemId: 'chapter_1',
    );
    notifier.value = const WorkspaceSelection.creating(
      section: NovelWorkspaceSection.materials,
    );
    notifier.toggleExpandedNode(NovelWorkspaceSection.chapters, 'volume_1');
    notifier.value = const WorkspaceSelection(
      section: NovelWorkspaceSection.chapters,
      itemId: 'chapter_2',
    );
    notifier.toggleExpandedNode(NovelWorkspaceSection.chapters, 'volume_1');
    notifier.ensureExpandedNode(NovelWorkspaceSection.chapters, 'volume_2');
    await notifier.flush();

    final rows = await database.appStateDao.getAllByPrefix(
      novelWorkspaceAppStateKeyPrefix,
    );
    expect(rows, hasLength(1));
    final decoded = jsonDecode(rows.values.single) as Map<String, dynamic>;
    expect(decoded['selection'], <String, dynamic>{
      'section': 'chapters',
      'itemId': 'chapter_2',
    });
    expect(
      (decoded['expandedNodes'] as Map<String, dynamic>)['chapters'],
      <String>['volume_2'],
    );
  });

  test('navigation selected during restore overrides stored state', () async {
    final database = AppDatabase.forTest(NativeDatabase.memory());
    const novelId = 'novel_navigation';
    await database.appStateDao.set(
      key: novelWorkspaceAppStateKey(novelId),
      value: jsonEncode(<String, dynamic>{
        'version': 1,
        'selection': <String, dynamic>{
          'section': 'chapters',
          'itemId': 'stored_chapter',
        },
        'expandedNodes': <String, dynamic>{},
      }),
    );
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    final provider = novelWorkspaceStateControllerProvider(novelId);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await database.close();
    });

    final notifier = container.read(provider.notifier);
    notifier.value = const WorkspaceSelection(
      section: NovelWorkspaceSection.characters,
      itemId: 'requested_character',
    );
    await notifier.ready;
    await notifier.flush();

    expect(
      container.read(provider).selection,
      const WorkspaceSelection(
        section: NovelWorkspaceSection.characters,
        itemId: 'requested_character',
      ),
    );
    final decoded =
        jsonDecode(
              (await database.appStateDao.get(
                novelWorkspaceAppStateKey(novelId),
              ))!,
            )
            as Map<String, dynamic>;
    expect(decoded['selection'], <String, dynamic>{
      'section': 'characters',
      'itemId': 'requested_character',
    });
  });

  test(
    'keeps different novels isolated and tolerates malformed JSON',
    () async {
      final database = AppDatabase.forTest(NativeDatabase.memory());
      await database.appStateDao.set(
        key: novelWorkspaceAppStateKey('novel_bad'),
        value: '{broken',
      );
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      final badProvider = novelWorkspaceStateControllerProvider('novel_bad');
      final otherProvider = novelWorkspaceStateControllerProvider(
        'novel_other',
      );
      final badSubscription = container.listen(badProvider, (_, _) {});
      final otherSubscription = container.listen(otherProvider, (_, _) {});
      addTearDown(() async {
        badSubscription.close();
        otherSubscription.close();
        container.dispose();
        await database.close();
      });

      await container.read(badProvider.notifier).ready;
      await container.read(otherProvider.notifier).ready;
      expect(
        container.read(badProvider).selection,
        const WorkspaceSelection.overview(),
      );
      container.read(otherProvider.notifier).value = const WorkspaceSelection(
        section: NovelWorkspaceSection.characters,
        itemId: 'character_1',
      );
      await container.read(otherProvider.notifier).flush();

      expect(
        await database.appStateDao.get(novelWorkspaceAppStateKey('novel_bad')),
        '{broken',
      );
      expect(
        await database.appStateDao.get(
          novelWorkspaceAppStateKey('novel_other'),
        ),
        isNotNull,
      );
    },
  );
}

// 职责: 实体关系图侧边栏列表测试 — 验证支持关系图谱的实体类型都展示在筛选与列表中。
// 关联文件:
//   lib/shared/entity_graph/entity_list_section.dart
//   lib/shared/entity_graph/data.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
//   assets/translations/en/entity.json
//   assets/translations/zh-CN/entity.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/entity_graph/entity_graph.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('shows every graph-supported entity type in sidebar filters', (
    tester,
  ) async {
    String? selectedKey;

    await tester.pumpWidget(
      _wrap(
        EntityListSection(
          characters: [_character(id: 'char_1', name: 'Aster')],
          factions: [_item(id: 'faction_1', type: entityTypeFaction)],
          skills: [_item(id: 'skill_1', type: entityTypeSkill)],
          items: [_item(id: 'item_1', type: entityTypeItem)],
          creatures: [_item(id: 'creature_1', type: entityTypeCreature)],
          selectedEntityKey: selectedKey,
          onEntitySelected: (key) => selectedKey = key,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Relationship Graph'), findsOneWidget);
    expect(find.text('All 5'), findsOneWidget);
    expect(find.text('Character 1'), findsOneWidget);
    expect(find.text('Faction 1'), findsOneWidget);
    expect(find.text('Skill 1'), findsOneWidget);
    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('Creature 1'), findsOneWidget);

    expect(find.text('Aster'), findsOneWidget);
    expect(find.text('faction_1 title'), findsOneWidget);
    expect(find.text('skill_1 title'), findsOneWidget);
    expect(find.text('item_1 title'), findsOneWidget);
    expect(find.text('creature_1 title'), findsOneWidget);
  });
}

Widget _wrap(Widget child) {
  return ProviderScope(
    child: EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: SizedBox(width: 320, height: 900, child: child),
              ),
            ),
          );
        },
      ),
    ),
  );
}

CharacterProfile _character({required String id, required String name}) {
  final now = DateTime(2024);
  return CharacterProfile(
    id: id,
    name: name,
    role: characterRoleSupporting,
    gender: '',
    aliases: const [],
    tags: const [],
    biography: '',
    appearance: '',
    description: '',
    identity: '',
    age: '',
    motivation: '',
    arc: '',
    personality: '',
    behaviorTags: const [],
    currentState: '',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

Item _item({required String id, required String type}) {
  final now = DateTime(2024);
  return Item(
    id: id,
    type: type,
    title: '$id title',
    content: '',
    status: 'active',
    category: '',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

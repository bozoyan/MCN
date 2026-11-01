// 职责: 验证侧栏长物品列表按可视范围延迟创建，避免一次性构建全部树行。
// 关联文件:
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/sidebar.json
//   assets/translations/zh-CN/sidebar.json

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/widgets/sidebar/sidebar.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('builds offscreen item rows only after they enter the viewport', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    await tester.pumpWidget(_wrapSidebar(items: _items(100)));
    await tester.pumpAndSettle();

    // 图鉴分组默认折叠，先展开「物品」再验证组内长列表的惰性构建。
    // 本文件用 en locale，分组标题是 Items（chip 是「Items 100」，不会撞）。
    await tester.tap(find.text('Items'));
    await tester.pumpAndSettle();

    expect(find.text('Item 99'), findsNothing);

    await tester.dragUntilVisible(
      find.text('Item 99'),
      find.byKey(const ValueKey('sidebar-section-list-compendium')),
      const Offset(0, -300),
    );

    expect(find.text('Item 99'), findsOneWidget);
  });
}

Widget _wrapSidebar({required List<Item> items}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: [
            appSettingsNotifierProvider.overrideWith(
              _TestAppSettingsNotifier.new,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: LeftSidebar(
                  novelTitle: 'Test novel',
                  currentNovelId: 'novel-1',
                  databasePath: null,
                  selection: const WorkspaceSelection(
                    section: NovelWorkspaceSection.items,
                  ),
                  chapters: const [],
                  worldbuildingEntries: const [],
                  outlineEntries: const [],
                  materialEntries: const [],
                  characterProfiles: const [],
                  skillEntries: const [],
                  items: items,
                  factionEntries: const [],
                  creatureEntries: const [],
                  foreshadowings: const [],
                  maps: const [],
                  locations: const [],
                  onSelect: (_) {},
                  onEditDetails: () {},
                  onCreateChapter: () async {},
                  onCollapse: () {},
                  onExpand: () {},
                  onSwitchNovel: (_) {},
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

List<Item> _items(int count) {
  final now = DateTime.utc(2026, 1, 1);
  return List.generate(
    count,
    (index) => Item(
      id: 'item-$index',
      type: 'item',
      title: 'Item $index',
      content: '',
      status: '',
      category: '',
      sortOrder: index,
      createdAt: now,
      updatedAt: now,
      deletedAt: now,
    ),
  );
}

class _TestAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async {
    return AppSettings(
      theme: AppTheme.reveric,
      themeMode: AppThemeMode.light,
      language: 'en',
      aiSettings: AiSettings.defaults(),
    );
  }
}

// 职责: 图鉴中栏的黄金图与筛选行为 — 势力/生物/物品/技能合并为一个入口后，
//       验证分组展示、类型 chip 过滤与分组折叠。
// 关联文件:
//   lib/desktop/widgets/sidebar/sections.dart
//   lib/desktop/widgets/sidebar/rail.dart
//   lib/shared/components/collapsible_list_group.dart
//   lib/shared/components/reveric_filter_chip.dart

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/native.dart';
import 'package:reveric/desktop/widgets/sidebar/sidebar.dart';
import 'package:reveric/shared/database/app_database.dart' show AppDatabase;
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await _loadFont('LXGWWenKai', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Georgia', 'assets/fonts/LXGWWenKai-Regular.ttf');
  });

  setUp(() => rootBundle.clear());

  testWidgets('图鉴：分组展示、类型筛选与分组折叠', (tester) async {
    tester.view.physicalSize = const Size(460, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    final database = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(_wrapSidebar(database));
    await tester.pumpAndSettle();

    // 四类分组默认全部折叠：合计可达上千条，一进来就铺开没法用。
    expect(find.text('势力'), findsOneWidget);
    expect(find.text('生物'), findsOneWidget);
    expect(find.text('物品'), findsOneWidget);
    expect(find.text('技能'), findsOneWidget);
    expect(find.text('炎盟'), findsNothing);
    expect(find.text('火蟒兽'), findsNothing);

    await expectLater(
      find.byType(LeftSidebar),
      matchesGoldenFile('goldens/compendium_panel.png'),
    );

    // 点分组标题展开，只影响该分组。
    await tester.tap(find.text('势力'));
    await tester.pumpAndSettle();
    expect(find.text('炎盟'), findsOneWidget);
    expect(find.text('魂殿'), findsOneWidget);
    expect(find.text('火蟒兽'), findsNothing);

    // 类型 chip 过滤到具体类型时自动展开该组，否则面板看着是空的。
    // chip 文案是「标签 计数」，与同名的分组标题行区分开。
    await tester.tap(find.text('生物 1'));
    await tester.pumpAndSettle();
    expect(find.text('火蟒兽'), findsOneWidget);
    expect(find.text('炎盟'), findsNothing);
    expect(find.text('玄重尺'), findsNothing);
    expect(find.text('焚决'), findsNothing);
  });
}

Item _item({
  required String id,
  required String type,
  required String title,
  required int sortOrder,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Item(
    id: id,
    type: type,
    title: title,
    content: '',
    status: '',
    category: '',
    sortOrder: sortOrder,
    createdAt: now,
    updatedAt: now,
    deletedAt: now,
  );
}

Widget _wrapSidebar(AppDatabase database) {
  return EasyLocalization(
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            appSettingsNotifierProvider.overrideWith(
              _TestAppSettingsNotifier.new,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric
                .toThemeData(fontFamily: 'LXGWWenKai')
                .copyWith(platform: TargetPlatform.macOS),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: LeftSidebar(
                  novelTitle: '斗破苍穹',
                  currentNovelId: 'novel-1',
                  databasePath: null,
                  selection: const WorkspaceSelection(
                    section: NovelWorkspaceSection.factions,
                  ),
                  chapters: const [],
                  worldbuildingEntries: const [],
                  outlineEntries: const [],
                  materialEntries: const [],
                  characterProfiles: const [],
                  skillEntries: [
                    _item(id: 's1', type: 'skill', title: '焚决', sortOrder: 0),
                    _item(id: 's2', type: 'skill', title: '八极崩', sortOrder: 1),
                  ],
                  items: [
                    _item(id: 'i1', type: 'item', title: '玄重尺', sortOrder: 0),
                  ],
                  factionEntries: [
                    _item(id: 'f1', type: 'faction', title: '炎盟', sortOrder: 0),
                    _item(id: 'f2', type: 'faction', title: '魂殿', sortOrder: 1),
                  ],
                  creatureEntries: [
                    _item(
                      id: 'c1',
                      type: 'creature',
                      title: '火蟒兽',
                      sortOrder: 0,
                    ),
                  ],
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

class _TestAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async {
    return AppSettings(
      theme: AppTheme.reveric,
      themeMode: AppThemeMode.light,
      language: 'zh-CN',
      aiSettings: AiSettings.defaults(),
    );
  }
}

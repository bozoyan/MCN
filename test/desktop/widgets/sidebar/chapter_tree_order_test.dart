// 职责: 验证倒序章节树会将根级新增章节入口置于章节列表顶部。
// 关联文件:
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/sidebar.json
//   assets/translations/zh-CN/sidebar.json

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/widgets/sidebar/sidebar.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/chapter.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('shows root add chapter before descending root chapters', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    await tester.pumpWidget(
      _wrapSidebar(
        chapters: [
          _chapter(id: 'chapter_1', chapterNum: 1, title: 'First'),
          _chapter(id: 'chapter_2', chapterNum: 2, title: 'Second'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      _top(tester, find.text('Add Chapter')),
      lessThan(_top(tester, find.text('Chapter 2 Second'))),
    );
    expect(
      _top(tester, find.text('Chapter 2 Second')),
      lessThan(_top(tester, find.text('Chapter 1 First'))),
    );
  });
}

Widget _wrapSidebar({required List<Chapter> chapters}) {
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
                    section: NovelWorkspaceSection.chapters,
                  ),
                  chapters: chapters,
                  worldbuildingEntries: const [],
                  outlineEntries: const [],
                  materialEntries: const [],
                  characterProfiles: const [],
                  skillEntries: const [],
                  items: const [],
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

class _TestAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async {
    return AppSettings(
      theme: AppTheme.reveric,
      themeMode: AppThemeMode.light,
      language: 'en',
      aiSettings: AiSettings.defaults(),
      chapterSortDescending: true,
    );
  }
}

double _top(WidgetTester tester, Finder finder) {
  return tester.getTopLeft(finder).dy;
}

Chapter _chapter({required String id, int? chapterNum, String? title}) {
  final now = DateTime.utc(2026, 1, 1);
  return Chapter(
    id: id,
    type: nodeTypeChapter,
    siblingOrder: 0,
    title: title,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
    chapterNum: chapterNum,
  );
}

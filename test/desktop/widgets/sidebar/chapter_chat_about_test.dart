// 职责: 验证章节右键菜单「对话本章」按卷内编号生成标识文本并回调。
// 关联文件:
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/desktop/widgets/sidebar/chapter_tree.dart
//   lib/shared/models/chapter.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/chapter.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  setUp(() => rootBundle.clear());

  testWidgets('chapter context menu sends volume-relative label to chat', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    String? captured;
    await tester.pumpWidget(
      _wrapSidebar(
        chapters: [
          _volume(id: 'volume_1', volumeNum: 1, title: '旧街来信'),
          _chapter(
            id: 'chp_1',
            chapterNum: 7,
            volumeChapterNum: 1,
            parentId: 'volume_1',
            title: '地下实验室',
          ),
        ],
        onChatAboutChapter: (text) async {
          captured = text;
        },
      ),
    );
    await tester.pumpAndSettle();

    final chapterLabel = find.text('Chapter 1 地下实验室');
    if (chapterLabel.evaluate().isEmpty) {
      await tester.tap(find.text('第 1 卷 · 旧街来信'));
      await tester.pumpAndSettle();
    }
    expect(chapterLabel, findsOneWidget);

    await tester.tap(chapterLabel, buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat about this chapter'));
    await tester.pumpAndSettle();

    expect(captured, '章节·第1卷·第1章·地下实验室·内容 chp_1');
  });
}

Widget _wrapSidebar({
  required List<Chapter> chapters,
  required Future<void> Function(String text) onChatAboutChapter,
}) {
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
                  onChatAboutChapter: onChatAboutChapter,
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

Chapter _volume({
  required String id,
  required int volumeNum,
  required String title,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Chapter(
    id: id,
    type: nodeTypeVolume,
    siblingOrder: 0,
    title: title,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
    volumeNum: volumeNum,
  );
}

Chapter _chapter({
  required String id,
  required int chapterNum,
  required int volumeChapterNum,
  required String parentId,
  required String title,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Chapter(
    id: id,
    type: nodeTypeChapter,
    parentId: parentId,
    siblingOrder: 1,
    title: title,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
    chapterNum: chapterNum,
    volumeChapterNum: volumeChapterNum,
  );
}

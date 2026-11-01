// 职责: 测试章节列表搜索选择器的无效选中值处理、去重、过滤与显示文案。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_list_dropdown.dart
//   lib/shared/models/chapter.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/workspace/chapter_list_dropdown.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/chapter.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('normalizes missing ids and duplicate chapter options', (
    tester,
  ) async {
    String? navigatedChapterId;
    await tester.pumpWidget(
      _wrapDropdown(
        ChapterListDropdown(
          selectedChapterId: 'chapter_missing',
          chapters: [_chapter(id: 'chapter_1', chapterNum: 1)],
          onChanged: (_) {},
          onNavigate: (chapterId) {
            navigatedChapterId = chapterId;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('无'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final chapter = _chapter(id: 'chapter_1', chapterNum: 1, title: '开端');
    String? formattedLabel;
    String? selectedChapterId;
    await tester.pumpWidget(
      _wrapDropdown(
        Builder(
          builder: (context) {
            formattedLabel = formatChapterListLabel(context, chapter);
            return ChapterListDropdown(
              selectedChapterId: 'chapter_1',
              chapters: [
                chapter,
                _chapter(id: 'chapter_1', chapterNum: 1, title: '重复开端'),
                _chapter(
                  id: 'volume_1',
                  type: nodeTypeVolume,
                  siblingOrder: -1,
                  title: '第一卷',
                  volumeNum: 1,
                ),
                _chapter(
                  id: 'chapter_2',
                  parentId: 'volume_1',
                  chapterNum: 2,
                  volumeChapterNum: 1,
                  title: '卷内开端',
                ),
                _chapter(
                  id: 'extra_1',
                  type: nodeTypeExtra,
                  chapterNum: null,
                  title: '番外',
                ),
              ],
              onChanged: (chapterId) {
                selectedChapterId = chapterId;
              },
              onNavigate: (chapterId) {
                navigatedChapterId = chapterId;
              },
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(formattedLabel, '第1章 开端');

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(navigatedChapterId, 'chapter_1');

    await tester.tap(find.text('第1章 开端'));
    await tester.pumpAndSettle();

    expect(find.text('第 1 卷 · 第一卷'), findsOneWidget);
    expect(find.text('第1章 卷内开端'), findsOneWidget);
    expect(find.text('番外'), findsNothing);

    await tester.tap(find.text('第 1 卷 · 第一卷'));
    await tester.pumpAndSettle();
    expect(selectedChapterId, isNull);

    await tester.enterText(find.byType(TextField), '卷内');
    // Search field is debounced (250ms); advance the fake clock past the debounce
    // before the dialog's ListView re-renders with filtered options.
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('第1章 开端')),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('第 1 卷 · 第一卷')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('第1章 卷内开端')),
      findsOneWidget,
    );

    await tester.tap(find.text('第1章 卷内开端'));
    await tester.pumpAndSettle();
    expect(selectedChapterId, 'chapter_2');
  });
}

Widget _wrapDropdown(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(body: Center(child: child)),
          ),
        );
      },
    ),
  );
}

Chapter _chapter({
  required String id,
  String type = nodeTypeChapter,
  String? parentId,
  int siblingOrder = 0,
  int? chapterNum,
  int? volumeNum,
  int? volumeChapterNum,
  String? title,
}) {
  final now = DateTime(2026);
  return Chapter(
    id: id,
    type: type,
    parentId: parentId,
    siblingOrder: siblingOrder,
    title: title,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
    volumeNum: volumeNum,
    chapterNum: chapterNum,
    volumeChapterNum: volumeChapterNum,
  );
}

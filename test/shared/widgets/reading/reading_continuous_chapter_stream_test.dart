// 职责: 验证连续章节流的锚点回看，以及章节高度变化时视口位置保持稳定。
// 关联文件:
//   lib/shared/widgets/reading/reading_content_view.dart
//   lib/shared/widgets/reading/reading_theme_palette.dart
//   lib/shared/models/chapter.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/chapter.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/reading/reading_content_view.dart';
import 'package:reveric/shared/widgets/reading/reading_theme_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(rootBundle.clear);

  testWidgets('keeps the previous chapter available above the current anchor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final chapters = [
      _chapter(id: 'chapter_1', title: 'First chapter', content: _body('A')),
      _chapter(id: 'chapter_2', title: 'Current chapter', content: _body('B')),
      _chapter(id: 'chapter_3', title: 'Next chapter', content: _body('C')),
    ];
    final activeChapterIds = <String>[];

    await tester.pumpWidget(
      _wrap(
        ProviderScope(
          overrides: [
            for (final chapter in chapters)
              chapterContentByIdProvider(
                path: 'reading_test_db',
                chapterId: chapter.id,
              ).overrideWith((ref) => Stream.value(chapter)),
          ],
          child: SizedBox(
            height: 500,
            child: ReadingContinuousChapterStream(
              databasePath: 'reading_test_db',
              chapters: chapters,
              initialChapterIndex: 1,
              palette: ReadingPalette.of(ReadingBackgroundTheme.white),
              fontFamily: 'Georgia',
              fontSize: 18,
              letterSpacing: 0,
              lineHeight: 1.8,
              paragraphSpacing: 1,
              horizontalMargin: 24,
              bold: false,
              onActiveChapterChanged: activeChapterIds.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(activeChapterIds, contains('chapter_2'));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 1400));
    await tester.pumpAndSettle();

    final previousTitle = find.text('First chapter');
    expect(previousTitle, findsOneWidget);
    expect(tester.getRect(previousTitle).bottom, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the visible text still when a chapter above it loads', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final chapters = [
      _chapter(id: 'chapter_1', title: 'First chapter', content: _body('A')),
      _chapter(
        id: 'chapter_2',
        title: 'Slow chapter',
        content: _body('B', count: 60),
      ),
      _chapter(id: 'chapter_3', title: 'Third chapter', content: _body('C')),
    ];
    final slowChapter = StreamController<Chapter?>();
    addTearDown(slowChapter.close);

    await tester.pumpWidget(
      _wrap(
        ProviderScope(
          overrides: [
            for (final chapter in chapters)
              chapterContentByIdProvider(
                path: 'reading_test_db',
                chapterId: chapter.id,
              ).overrideWith(
                (ref) => chapter.id == 'chapter_2'
                    ? slowChapter.stream
                    : Stream.value(chapter),
              ),
          ],
          child: SizedBox(
            height: 500,
            child: ReadingContinuousChapterStream(
              databasePath: 'reading_test_db',
              chapters: chapters,
              initialChapterIndex: 0,
              palette: ReadingPalette.of(ReadingBackgroundTheme.white),
              fontFamily: 'Georgia',
              fontSize: 18,
              letterSpacing: 0,
              lineHeight: 1.8,
              paragraphSpacing: 1,
              horizontalMargin: 24,
              bold: false,
              onActiveChapterChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 第二章仍是加载骨架时直接滑进第三章。
    final thirdTitle = find.text('Third chapter');
    await tester.dragUntilVisible(
      thirdTitle,
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    final topBefore = tester.getTopLeft(thirdTitle).dy;

    slowChapter.add(chapters[1]);
    await tester.pumpAndSettle();

    expect(thirdTitle, findsOneWidget);
    expect(tester.getTopLeft(thirdTitle).dy, moreOrLessEquals(topBefore));
    expect(tester.takeException(), isNull);
  });
}

Chapter _chapter({
  required String id,
  required String title,
  required String content,
}) {
  final now = DateTime(2026);
  return Chapter(
    id: id,
    type: nodeTypeChapter,
    siblingOrder: int.parse(id.substring(id.length - 1)),
    title: title,
    content: content,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

String _body(String label, {int count = 20}) {
  return List.generate(count, (index) => '$label paragraph $index').join('\n');
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return RevericTheme(
          data: RevericThemeData.reveric,
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: Scaffold(body: child),
          ),
        );
      },
    ),
  );
}

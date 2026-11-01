// 职责: 验证连续阅读在章节加载时展示文本骨架，并在内容到达后平滑切换。
// 关联文件:
//   lib/shared/widgets/reading/reading_content_view.dart
//   lib/shared/widgets/reading/reading_theme_palette.dart
//   lib/shared/models/chapter.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/reading.json
//   assets/translations/zh-CN/reading.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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

  testWidgets('uses a text skeleton instead of a spinner while loading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final chapter = _chapter();
    final chapterController = StreamController<Chapter?>();
    addTearDown(chapterController.close);

    await tester.pumpWidget(
      _wrap(
        ProviderScope(
          overrides: [
            chapterContentByIdProvider(
              path: 'reading_loading_test_db',
              chapterId: chapter.id,
            ).overrideWith((ref) => chapterController.stream),
          ],
          child: SizedBox(
            height: 500,
            child: ReadingContinuousChapterStream(
              databasePath: 'reading_loading_test_db',
              chapters: [chapter],
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
    await tester.pump();

    expect(
      find.byKey(const ValueKey('reading-chapter-loading-chapter_1')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    chapterController.add(chapter);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('reading-chapter-content-chapter_1')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Chapter _chapter() {
  final now = DateTime(2026);
  return Chapter(
    id: 'chapter_1',
    type: nodeTypeChapter,
    siblingOrder: 0,
    title: 'Current chapter',
    content: 'First paragraph\nSecond paragraph',
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
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

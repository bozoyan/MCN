// 职责: Patrol 阅读恢复验证 — 确认连续阅读按已保存章节及章内偏移恢复。
// 关联文件:
//   lib/shared/widgets/reading/reading_content_view.dart
//   lib/shared/widgets/reading/reading_theme_palette.dart
//   lib/shared/models/chapter.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

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
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _ChapterProgress = ({String chapterId, double scrollOffset});

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  patrolTest('restores a continuous reader at the saved chapter-local offset', (
    $,
  ) async {
    $.tester.view.devicePixelRatio = 1;
    $.tester.view.physicalSize = const Size(900, 700);
    addTearDown(() {
      $.tester.view.resetPhysicalSize();
      $.tester.view.resetDevicePixelRatio();
    });

    final chapters = [
      _chapter(id: 'chapter_1', title: 'First chapter', content: _body('A')),
      _chapter(id: 'chapter_2', title: 'Saved chapter', content: _body('B')),
      _chapter(id: 'chapter_3', title: 'Next chapter', content: _body('C')),
    ];
    final restoredProgress = <_ChapterProgress>[];

    await $.pumpWidgetAndSettle(
      _wrap(
        ProviderScope(
          overrides: [
            for (final chapter in chapters)
              chapterByIdProvider(
                path: 'reading_patrol_db',
                chapterId: chapter.id,
              ).overrideWith((ref) => Stream.value(chapter)),
          ],
          child: SizedBox(
            height: 500,
            child: ReadingContinuousChapterStream(
              databasePath: 'reading_patrol_db',
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
              onActiveChapterChanged: (_) {},
              onChapterProgressChanged: (chapterId, scrollOffset) {
                restoredProgress.add((
                  chapterId: chapterId,
                  scrollOffset: scrollOffset,
                ));
              },
              initialScrollOffset: 180,
            ),
          ),
        ),
      ),
    );

    expect($('Saved chapter'), findsOneWidget);
    final latest = restoredProgress.lastWhere(
      (progress) => progress.chapterId == 'chapter_2',
    );
    expect(latest.scrollOffset, closeTo(180, 2));
    expect($(CircularProgressIndicator), findsNothing);
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

String _body(String label) {
  return List.generate(
    80,
    (index) => '$label paragraph $index with enough text to fill the reader.',
  ).join('\n');
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

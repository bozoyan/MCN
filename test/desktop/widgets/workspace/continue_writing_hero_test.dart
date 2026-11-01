// 职责: 验证概览继续写作发送正确章节请求。
// 关联文件:
//   lib/desktop/widgets/workspace/hero.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/widgets/workspace/hero.dart';
import 'package:reveric/shared/models/chapter.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/app_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  for (final width in [480.0, 1100.0]) {
    for (final hasChapters in [false, true]) {
      testWidgets(
        'continue sends request at width $width, chapters $hasChapters',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final requests = <String>[];
          final selections = <WorkspaceSelection>[];
          final chapters = hasChapters
              ? [_chapter(7), _chapter(8)]
              : <Chapter>[];
          await tester.pumpWidget(
            ProviderScope(
              overrides: [appBackgroundActiveProvider.overrideWithValue(false)],
              child: _wrap(
                Scaffold(
                  body: SingleChildScrollView(
                    child: ContinueWritingHero(
                      chapters: chapters,
                      lastWrittenChapter: hasChapters ? chapters.first : null,
                      onContinueWriting: requests.add,
                      onSelectionChanged: selections.add,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(FilledButton));
          await tester.pump();
          expect(requests, [
            hasChapters ? 'Continue Chapter 8' : 'Start Chapter 1',
          ]);
          expect(selections, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}

Chapter _chapter(int number) => Chapter(
  id: 'chapter_$number',
  type: nodeTypeChapter,
  siblingOrder: number,
  chapterNum: number,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  deletedAt: notDeletedSentinel,
);

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) => RevericTheme(
        data: RevericThemeData.reveric,
        child: MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: child,
        ),
      ),
    ),
  );
}

// 职责: 验证移动端季管理在单层 sheet 内编辑、滚动和切换，键盘不遮挡提交。
// 关联文件:
//   lib/mobile/features/screenplay/season_manage_sheet.dart
//   lib/mobile/features/screenplay/episode_picker_sheet.dart
//   lib/shared/widgets/screenplay/season_manager.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reveric/shared/widgets/screenplay/season_manager.dart';
import 'package:reveric/shared/widgets/screenplay/episode_count.dart';
import 'package:reveric/shared/components/reveric_slidable_delete.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/features/screenplay/season_manage_sheet.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/models/novel_type.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'season actions and inline counts work on phone and desktop with keyboard',
    (tester) async {
      tester.view.physicalSize = Size(
        defaultTargetPlatform == TargetPlatform.macOS ? 1000 : 375,
        812,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final appDb = AppDatabase.forTest(NativeDatabase.memory());
      final contentDb = NovelContentDatabase.forTest(NativeDatabase.memory());
      final service = ScreenplayService(contentDb, novelId: 'screenplay_1');
      await service.createInitialStructure();
      final root = (await contentDb.screenplayDao.getRoot())!;
      const path = 'memory:mobile_season_manager';
      final novel = _screenplay(path);
      addTearDown(() async {
        await contentDb.close();
        await appDb.close();
      });
      await tester.pumpWidget(
        _wrap(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(appDb),
              novelContentDatabaseProvider(path).overrideWithValue(contentDb),
            ],
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showMobileScreenplaySeasonManager(
                    context,
                    novel: novel,
                    screenplayId: root.id,
                    onFlush: () async => true,
                  ),
                  child: const Text('Open seasons'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open seasons'));
      await tester.pumpAndSettle();
      // 只有一层 sheet —— 季选择和季管理已经合并，不再先弹一层列表。
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      final isMobile = defaultTargetPlatform == TargetPlatform.android;
      final semantics = tester.ensureSemantics();
      try {
        // A single remaining season must not expose an active delete action.
        if (isMobile) {
          expect(find.byType(RevericSlidableDelete), findsNothing);
        } else {
          await tester.tap(find.byTooltip('More actions'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            await contentDb.screenplayDao.getSeasons(root.id),
            hasLength(1),
          );
          Navigator.of(tester.element(find.text('Delete'))).pop();
          await tester.pumpAndSettle();
        }
        await service.createSeason(screenplayId: root.id);
        await tester.pumpAndSettle();
        final initialSeasons = await contentDb.screenplayDao.getSeasons(
          root.id,
        );
        final secondRow = find.byKey(ValueKey(initialSeasons.last.id));
        if (isMobile) {
          expect(find.byType(RevericSlidableDelete), findsNWidgets(2));
          expect(find.byTooltip('Delete'), findsNothing);
          await tester.drag(secondRow, const Offset(-250, 0));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete').hitTestable());
        } else {
          await tester.tap(find.byTooltip('More actions').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(await contentDb.screenplayDao.getSeasons(root.id), hasLength(2));
        expect(tester.takeException(), isNull);
        // Sorting still works after opening and dismissing the delete action.
        final list = tester.widget<ReorderableListView>(
          find.byType(ReorderableListView),
        );
        list.onReorderItem!(1, 0);
        await tester.pumpAndSettle();
        expect(
          (await contentDb.screenplayDao.getSeasons(root.id)).first.id,
          initialSeasons.last.id,
        );
        tester
            .widget<ReorderableListView>(find.byType(ReorderableListView))
            .onReorderItem!(0, 1);
        await tester.pumpAndSettle();
        final manager = find.byType(ScreenplaySeasonManager);
        final listHeight = tester.getSize(manager).height;
        expect(listHeight, lessThan(812 * 0.78));
        expect(find.text('Season 2'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final secondCount = find.descendant(
          of: secondRow,
          matching: find.byType(ScreenplayEpisodeCount),
        );
        expect(
          tester.getCenter(secondCount).dy,
          closeTo(tester.getCenter(find.text('Season 2')).dy, 1),
        );
        expect(find.byTooltip('Season settings'), findsNothing);
        await tester.tap(find.byTooltip('More actions').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Season settings'));
        await tester.pumpAndSettle();
        // 列表压成单行后，表单仍按内容定高，不拉满弹层上限。
        expect(tester.getSize(manager).height, lessThan(812 * 0.78));
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        await tester.enterText(
          find.byType(TextField).first,
          'A very long season title that needs room to wrap',
        );
        await tester.enterText(find.byType(TextField).last, '0');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.getBottomLeft(find.text('Save')).dy, lessThan(812 - 300));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNWidgets(2));
        expect(
          (await contentDb.screenplayDao.getSeasons(
            root.id,
          )).last.plannedEpisodeCount,
          isNull,
        );
        await tester.enterText(find.byType(TextField).last, '8');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.text('1/8 eps'), findsOneWidget);
        final seasonTitle = find.descendant(
          of: secondRow,
          matching: find.textContaining('A very long season title'),
        );
        expect(
          tester.getCenter(find.text('1/8 eps')).dy,
          closeTo(tester.getCenter(seasonTitle).dy, 1),
        );
        expect(
          (await contentDb.screenplayDao.getSeasons(
            root.id,
          )).last.plannedEpisodeCount,
          8,
        );
        expect(tester.takeException(), isNull);

        // 外部新增季必须直接进入当前弹层的列表，并且新增入口始终可见。
        for (var index = 0; index < 8; index += 1) {
          await service.createSeason(screenplayId: root.id);
        }
        await tester.pumpAndSettle();
        expect(find.text('Add season'), findsOneWidget);
        await tester.drag(
          find.byType(ReorderableListView),
          const Offset(0, -1800),
        );
        await tester.pumpAndSettle();
        expect(find.text('Season 10'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final lastSeason = (await contentDb.screenplayDao.getSeasons(
          root.id,
        )).last;
        if (isMobile) {
          await tester.drag(
            find.byKey(ValueKey(lastSeason.id)),
            const Offset(-250, 0),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete').hitTestable());
        } else {
          await tester.tap(find.byTooltip('More actions').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(await contentDb.screenplayDao.getSeasons(root.id), hasLength(9));
        expect(find.byKey(ValueKey(lastSeason.id)), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Add season'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          await contentDb.screenplayDao.getSeasons(root.id),
          hasLength(10),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.macOS,
    }),
  );
}

Novel _screenplay(String databasePath) {
  final now = DateTime(2026);
  return Novel(
    id: 'screenplay_1',
    title: 'Screenplay Test',
    authorName: '',
    description: '',
    status: contentStatusInProgress,
    type: novelTypeOriginal,
    contentKind: contentKindScreenplay,
    contentDatabasePath: databasePath,
    wordCount: 0,
    draft: false,
    category: '',
    tags: const [],
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Widget _wrap(Widget child) {
  if (child is ProviderScope) {
    return ProviderScope(overrides: child.overrides, child: _wrap(child.child));
  }
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

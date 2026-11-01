// 职责: 验证作品页类型筛选的导航稳定与滚动保持，以及混排、筛选、统计、导出和剧本入口。
// 关联文件:
//   lib/mobile/pages/library_page.dart
//   lib/mobile/features/screenplay/library_meta.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:drift/native.dart';
import 'package:reveric/shared/database/novel_content_database.dart'
    show NovelContentDatabase;
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/mobile/features/screenplay/editor_page.dart';
import 'package:reveric/mobile/features/screenplay/library_meta.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reveric/shared/widgets/novel_export_form.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/mobile/pages/library_page.dart';
import 'package:reveric/mobile/widgets/segmented_tabs.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/models/novel_type.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/initialization/collection_seeds.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    if (Platform.environment['LIBRARY_SCREENSHOT_DIR'] != null) {
      for (final family in [
        'Roboto',
        '.SF UI Text',
        '.SF UI Display',
        'Ahem',
      ]) {
        await (FontLoader(family)
              ..addFont(rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf')))
            .load();
      }
    }
  });
  setUp(() => rootBundle.clear());

  testWidgets('shelves separate content kinds and open screenplay workspaces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final appDb = AppDatabase.forTest(NativeDatabase.memory());
    final contentDb = NovelContentDatabase.forTest(NativeDatabase.memory());
    final service = ScreenplayService(contentDb);
    final initial = await service.createInitialStructure();
    final root = (await contentDb.screenplayDao.getRoot())!;
    await service.createScene(
      screenplayId: root.id,
      episodeId: initial.episodeId,
    );
    const path = 'memory:library_screenplay';
    final script = _novel(
      id: 'script',
      title: 'Screenplay example',
      kind: contentKindScreenplay,
      path: path,
    );
    final novel = _novel(tags: ['Novel tag']);
    // 书架按集合取作品，集合结果来自数据库，作品和默认集合都得真的落库。
    for (final work in [novel, script]) {
      await appDb.into(appDb.novels).insert(work.toCompanion(true));
    }
    await seedCollections(
      appDb,
      names: {
        'all': 'All',
        'in_progress': 'In progress',
        'finished': 'Finished',
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(appDb),
          novelContentDatabaseProvider(path).overrideWithValue(contentDb),
          novelsProvider.overrideWith((ref) => Stream.value([novel, script])),
        ],
        child: _wrap(const MobileLibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    // 默认全部类型：小说和剧本在同一个网格里。
    expect(_inGrid('Compact test novel'), findsWidgets);
    expect(find.byType(MobileScreenplayMetaLabel), findsOneWidget);
    final tabs = tester.element(find.byType(MobileSegmentedTabs));
    final tabsRect = tester.getRect(find.byType(MobileSegmentedTabs));
    final search = tester.element(find.byType(TextField));
    await tester.tap(_typeTab('Screenplay'));
    await tester.pump();
    expect(
      find.byType(MobileSegmentedTabs),
      findsOneWidget,
      reason: 'Navigation must remain visible while the new shelf loads',
    );
    expect(tester.element(find.byType(MobileSegmentedTabs)), same(tabs));
    expect(tester.getRect(find.byType(MobileSegmentedTabs)), tabsRect);
    expect(tester.element(find.byType(TextField)), same(search));
    await tester.pumpAndSettle();
    expect(_inGrid('Compact test novel'), findsNothing);
    expect(find.byType(MobileScreenplayMetaLabel), findsOneWidget);
    expect(find.text('1 eps · 1 scenes'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'absent');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(MobileScreenplayMetaLabel), findsNothing);
    // 书架非空只是被筛空：提示无匹配并可一键清除，而不是「还没有剧本」。
    expect(find.text('No screenplays yet'), findsNothing);
    expect(find.text('No matching works'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('absent'), findsNothing);
    expect(find.byType(MobileScreenplayMetaLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.longPress(find.byType(MobileScreenplayMetaLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.byType(NovelExportForm), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Script'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MobileScreenplayMetaLabel));
    await tester.pumpAndSettle();
    expect(find.byType(MobileScreenplayEditorPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await contentDb.close();
    await appDb.close();
  });

  testWidgets(
    'switching work type keeps navigation and scroll position in place',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase.forTest(NativeDatabase.memory());
      addTearDown(db.close);
      final works = [
        _novel(id: 'draft', title: 'Draft work', draft: true),
        for (var i = 0; i < 12; i++) _novel(id: 'novel_$i', title: 'Novel $i'),
        for (var i = 0; i < 8; i++)
          _novel(
            id: 'script_$i',
            title: 'Screenplay $i',
            kind: contentKindScreenplay,
          ),
      ];
      for (final work in works) {
        await db.into(db.novels).insert(work.toCompanion(true));
      }
      await seedCollections(
        db,
        names: {
          'all': 'All',
          'in_progress': 'In progress',
          'finished': 'Finished',
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            novelsProvider.overrideWith((ref) => Stream.value(works)),
          ],
          child: _wrap(
            const MobileLibraryPage(),
            theme: RevericThemeData.revericDark,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tabs = find.byType(MobileSegmentedTabs);
      final tabsElement = tester.element(tabs);
      final createRect = tester.getRect(find.byTooltip('New').first);
      await _capture(tester, 'works');

      ScrollPosition position() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -280));
      await tester.pumpAndSettle();
      final offset = position().pixels;
      expect(offset, greaterThan(200));
      final tabsRect = tester.getRect(tabs);
      // 类型是同一个作品库里的筛选：换类型不换页面，导航和滚动位置都留在原地。
      await tester.tap(_typeTab('Screenplay'));
      await tester.pump();
      expect(tester.element(tabs), same(tabsElement));
      expect(tester.getRect(tabs), tabsRect);
      await tester.pumpAndSettle();
      expect(position().pixels, closeTo(offset, 1));
      expect(tester.getRect(find.byTooltip('New').first), createRect);
      expect(_inGrid('Novel 0'), findsNothing);
      await _capture(tester, 'screenplays');

      // 在前一次加载完成前再次切换，导航仍是同一个对象。
      for (final label in ['Novel', 'Screenplay', 'All']) {
        await tester.tap(_typeTab(label));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.element(tabs), same(tabsElement));
      }
      await tester.pumpAndSettle();
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

/// 继续写和最近也会列出作品，断言只看作品网格。
Finder _inGrid(String title) =>
    find.descendant(of: find.byType(SliverGrid), matching: find.text(title));

Finder _typeTab(String label) => find.descendant(
  of: find.byType(MobileSegmentedTabs),
  matching: find.text(label),
);

Novel _novel({
  int wordCount = 0,
  String id = 'novel_test',
  String title = 'Compact test novel',
  String kind = contentKindNovel,
  String? path,
  List<String> tags = const [],
  bool draft = false,
}) {
  final now = DateTime(2026);
  return Novel(
    id: id,
    title: title,
    authorName: '',
    description: '',
    status: contentStatusInProgress,
    type: novelTypeOriginal,
    contentKind: kind,
    contentDatabasePath: path,
    wordCount: wordCount,
    draft: draft,
    category: '',
    tags: tags,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Widget _wrap(
  Widget child, {
  Locale locale = const Locale('en'),
  RevericThemeData theme = RevericThemeData.reveric,
}) {
  final mobileTheme = theme.copyWith(typography: RevericTypography.mobile);
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: locale,
    child: Builder(
      builder: (context) {
        return RevericTheme(
          data: mobileTheme,
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: mobileTheme.toThemeData().copyWith(
              platform: TargetPlatform.iOS,
            ),
            home: RepaintBoundary(
              key: const ValueKey('library-capture'),
              child: Scaffold(body: child),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['LIBRARY_SCREENSHOT_DIR'];
  if (directory == null) {
    return;
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('library-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

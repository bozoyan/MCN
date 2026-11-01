// 职责: 验证双端伏笔位置受控展示、清空回传、失效目标和移动选择器取消，并保存渲染证据。
// 关联文件:
//   lib/shared/widgets/foreshadowing/position_links.dart
//   lib/shared/services/novel_content.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/foreshadowing/position_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    for (final family in ['LXGWWenKai', 'Georgia', 'Roboto', 'Ahem']) {
      final font = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf'));
      await font.load();
    }
  });
  testWidgets(
    'both platforms retain missing references and cancel safely',
    (tester) async {
      for (final mobile in [false, true]) {
        tester.view.physicalSize = Size(mobile ? 375 : 900, mobile ? 812 : 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final db = NovelContentDatabase.forTest(NativeDatabase.memory());
        addTearDown(db.close);
        final service = NovelContentService(db);
        final screenplay = ScreenplayService(db);
        late String id;
        late String scene;
        await tester.runAsync(() async {
          final initial = await screenplay.createInitialStructure();
          final root = (await db.screenplayDao.getRoot())!;
          scene = await screenplay.createScene(
            screenplayId: root.id,
            episodeId: initial.episodeId,
            synopsis:
                'A long scene description for testing the compact position selector',
          );
          id = await service.createForeshadowing(
            title: 'Clue',
            setup: 'Keep this draft',
            setupSceneId: scene,
          );
        });
        String? navigated;
        ForeshadowingPositionIds? positions;
        final boundary = GlobalKey();
        final theme = RevericThemeData.reveric.toThemeData(
          fontFamily: 'LXGWWenKai',
        );
        final renderedTheme = theme.copyWith(
          textButtonTheme: TextButtonThemeData(
            style: theme.textButtonTheme.style!.copyWith(
              textStyle: WidgetStatePropertyAll(
                RevericThemeData.reveric.typography.uiSemibold.copyWith(
                  fontFamily: 'LXGWWenKai',
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              novelContentDatabaseProvider('test').overrideWithValue(db),
              novelContentServiceProvider('test').overrideWithValue(service),
            ],
            child: EasyLocalization(
              supportedLocales: const [Locale('en')],
              path: 'assets/translations',
              assetLoader: const MergingAssetLoader(),
              startLocale: const Locale('en'),
              fallbackLocale: const Locale('en'),
              child: Builder(
                builder: (context) => MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  theme: renderedTheme,
                  home: RevericTheme(
                    data: RevericThemeData.reveric,
                    child: Scaffold(
                      backgroundColor: RevericThemeData.reveric.colors.canvas,
                      body: RepaintBoundary(
                        key: boundary,
                        child: Container(
                          color: RevericThemeData.reveric.colors.canvas,
                          padding: const EdgeInsets.all(RevericSpacing.x2l),
                          child: Consumer(
                            builder: (context, ref, _) {
                              final entries = ref
                                  .watch(foreshadowingsProvider('test'))
                                  .value;
                              if (entries == null) {
                                return const SizedBox.shrink();
                              }
                              return StatefulBuilder(
                                builder: (context, setState) {
                                  positions ??= foreshadowingPositionIdsOf(
                                    entries.single,
                                  );
                                  return ForeshadowingPositionLinks(
                                    databasePath: 'test',
                                    value: positions!,
                                    onChanged: (next) =>
                                        setState(() => positions = next),
                                    mobile: mobile,
                                    onNavigate: (target) =>
                                        navigated = target.id,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Setup position'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Open position').first);
        expect(navigated, scene);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final rendered =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await rendered.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await File(
            '/tmp/foreshadowing-position-${mobile ? "mobile" : "desktop"}.png',
          ).writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
        if (mobile) {
          await tester.tap(find.text('None'));
          await tester.pumpAndSettle();
          Navigator.of(tester.element(find.byType(ListView).last)).pop();
          await tester.pumpAndSettle();
          expect(positions!.setupSceneId, scene);
        }
        await tester.runAsync(() => screenplay.deleteScene(scene));
        await tester.pumpAndSettle();
        expect(find.text('Target unavailable'), findsOneWidget);
        // 清空走候选里的「None」，两端都没有单独的清除按钮。
        expect(find.byTooltip('Clear'), findsNothing);
        // 回收位置本身也显示 None；只点选择器打开后新出现的那个选项。
        final shownNone = find.text('None').evaluate().toSet();
        await tester.tap(find.text('Target unavailable'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byElementPredicate(
            (element) =>
                find.text('None').evaluate().contains(element) &&
                !shownNone.contains(element),
          ),
        );
        await tester.pumpAndSettle();
        // 受控组件只回传新值，不直接写库。
        expect(positions!.setupSceneId, isNull);
        expect(positions!.setupChapterId, isNull);
        final entry = await tester.runAsync(
          () => service.getForeshadowingById(id),
        );
        expect(entry!.setupSceneId, scene);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

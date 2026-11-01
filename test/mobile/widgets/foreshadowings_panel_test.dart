// 职责: 验证移动端伏笔列表在剧本作品里显示场次位置，而不是恒显示未关联占位。
// 关联文件:
//   lib/mobile/widgets/foreshadowings_panel.dart
//   lib/shared/widgets/foreshadowing/position_links.dart
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/mobile/widgets/foreshadowings_panel.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'screenplay entries show the linked scene, not the placeholder',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      addTearDown(db.close);
      final service = NovelContentService(db);
      await tester.runAsync(() async {
        final screenplay = ScreenplayService(db);
        final initial = await screenplay.createInitialStructure();
        final root = (await db.screenplayDao.getRoot())!;
        final scene = await screenplay.createScene(
          screenplayId: root.id,
          episodeId: initial.episodeId,
          synopsis: 'The clue is planted here',
        );
        await service.createForeshadowing(title: 'Clue', setupSceneId: scene);
        await service.createForeshadowing(title: 'Unlinked');
      });

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
                home: RevericTheme(
                  data: RevericThemeData.reveric,
                  child: Scaffold(
                    body: MobileForeshadowingsPanel(
                      novelId: 'work',
                      databasePath: 'test',
                      onCreate: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 关联了场次的条目显示「第 N 集 · 第 M 场」；曾经这里恒显示「铺垫位置」，
      // 因为卡片只查章节表，而剧本的位置存在 setup_scene_id。
      expect(find.text('Episode 1 · Scene 1'), findsOneWidget);
      expect(find.text('Setup position'), findsOneWidget);
      expect(find.text('Unfulfilled'), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      // 卸载后再推一帧，让 drift stream 关闭时排的零延时 timer 跑完。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

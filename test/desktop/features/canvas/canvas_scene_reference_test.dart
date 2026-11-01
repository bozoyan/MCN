// 职责: 验证画布场次卡片、梗概与选择器共享投影，并正确处理分组、搜索及重复引用。
// 关联文件:
//   lib/desktop/features/canvas/scene_reference.dart
//   lib/desktop/features/canvas/widgets/canvas_resource_picker.dart
//   lib/desktop/features/canvas/widgets/canvas_node_widget.dart
//   lib/shared/providers/canvas_providers.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'dart:async';

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/scene_reference.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_flow_adapter.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_node_widget.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_resource_picker.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/canvas_scene_reference.dart';
import 'package:reveric/shared/models/screenplay.dart';
import 'package:reveric/shared/providers/canvas_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/canvas_service.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const path = 'memory:canvas-scene-widget';
  late NovelContentDatabase db;
  late ProviderContainer container;
  late CanvasService canvas;
  late ScreenplayService screenplay;
  late CreatedSeason initial;
  late String rootId;
  late String canvasId;
  late String sceneId;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() async {
    rootBundle.clear();
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    screenplay = ScreenplayService(db);
    canvas = CanvasService(db);
    initial = await screenplay.createInitialStructure();
    rootId = (await db.screenplayDao.getRoot())!.id;
    sceneId = await screenplay.createScene(
      screenplayId: rootId,
      episodeId: initial.episodeId,
      title: 'Arrival',
      synopsis: 'The last train arrives.',
    );
    canvasId = await canvas.createCanvas(name: 'Story');
    container = ProviderContainer(
      overrides: [
        novelContentDatabaseProvider(path).overrideWithValue(db),
        novelContentServiceProvider(
          path,
        ).overrideWithValue(NovelContentService(db)),
      ],
    );
    container.listen(canvasSceneReferencesProvider(path), (_, _) {});
    await container.read(canvasSceneReferencesProvider(path).future);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> waitForScenes(
    bool Function(Map<String, CanvasSceneReference>) predicate,
  ) async {
    final done = Completer<void>();
    final sub = container.listen(canvasSceneReferencesProvider(path), (
      _,
      value,
    ) {
      if (!value.isLoading &&
          value.value != null &&
          predicate(value.value!) &&
          !done.isCompleted) {
        done.complete();
      }
    }, fireImmediately: true);
    try {
      await done.future.timeout(const Duration(seconds: 5));
    } finally {
      sub.close();
    }
  }

  Widget wrap(Widget child) =>
      UncontrolledProviderScope(container: container, child: _wrap(child));

  testWidgets(
    'duplicate cards update title and location while details expose synopsis and stable open ID',
    (tester) async {
      final nodes = await tester.runAsync(() async {
        for (var i = 0; i < 2; i++) {
          await canvas.addNode(
            canvasId: canvasId,
            type: canvasNodeTypeReference,
            refType: canvasNodeRefTypeScreenplayScene,
            refId: sceneId,
            x: 0,
            y: 0,
          );
        }
        return db.canvasDao.getNodesByCanvas(canvasId);
      });
      String? opened;
      final flowNodes = nodes!
          .map(
            (node) => canvasNodeToFlowNode(
              node,
              colors: RevericThemeData.reveric.colors,
            ),
          )
          .toList();
      await tester.pumpWidget(
        wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final node in flowNodes)
                SizedBox(
                  width: 320,
                  height: 80,
                  child: CanvasNodeCard(node: node, databasePath: path),
                ),
              SizedBox(
                width: 320,
                child: CanvasSceneReferenceDetails(
                  databasePath: path,
                  sceneId: sceneId,
                  onOpen: (id) => opened = id,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Arrival'), findsNWidgets(3));
      expect(find.text('Season 1 / Episode 1 / Scene 1'), findsNWidgets(3));
      expect(find.text('The last train arrives.'), findsOneWidget);
      await tester.tap(find.text('Open scene'));
      expect(opened, sceneId);
      await tester.runAsync(() async {
        final target = await screenplay.createSeason(screenplayId: rootId);
        await screenplay.updateScene(sceneId: sceneId, title: 'Departure');
        await screenplay.moveSceneToEpisodeEnd(sceneId, target.episodeId);
        await waitForScenes(
          (items) =>
              items[sceneId]?.season.id == target.seasonId &&
              items[sceneId]?.scene.title == 'Departure',
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('Arrival'), findsNothing);
      expect(find.text('Departure'), findsNWidgets(3));
      expect(find.text('Season 2 / Episode 1 / Scene 1'), findsNWidgets(3));
      await tester.runAsync(() async {
        await screenplay.updateScene(sceneId: sceneId, title: '');
        await waitForScenes((items) => items[sceneId]?.scene.title == '');
      });
      await tester.pumpAndSettle();
      expect(find.text('Scene 1'), findsNWidgets(3));
      await tester.runAsync(() async {
        await screenplay.deleteScene(sceneId);
        await waitForScenes((items) => !items.containsKey(sceneId));
      });
      await tester.pumpAndSettle();
      expect(find.text('Open scene'), findsNothing);
      expect(find.text('The last train arrives.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'picker groups seasons, debounces scene-number search, disables used resources and adds current IDs',
    (tester) async {
      late String unnamed;
      await tester.runAsync(() async {
        await canvas.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: canvasNodeRefTypeScreenplayScene,
          refId: sceneId,
          x: 0,
          y: 0,
        );
        final target = await screenplay.createSeason(screenplayId: rootId);
        await screenplay.createScene(
          screenplayId: rootId,
          episodeId: target.episodeId,
          title: 'Elsewhere',
        );
        unnamed = await screenplay.createScene(
          screenplayId: rootId,
          episodeId: initial.episodeId,
        );
        await waitForScenes((items) => items.length == 3);
        // 在真实 async zone 启动并等待 DB stream，避免把 FakeAsync 队列中的
        // 首次发射放到 runAsync 里等待（真实 zone 不会推进 FakeAsync）。
        final content = canvasContentStreamProvider((
          canvasId: canvasId,
          databasePath: path,
        ));
        container.listen(content, (_, _) {});
        await container.read(content.future);
      });
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showCanvasResourcePicker(
                context: context,
                databasePath: path,
                canvasId: canvasId,
                viewportCenter: const Offset(56, 44),
              ),
              child: const Text('Pick'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      expect(find.text('Scenes · Season 1 / Episode 1'), findsOneWidget);
      expect(find.text('Scenes · Season 2 / Episode 1'), findsOneWidget);
      expect(find.text('On canvas'), findsOneWidget);
      await tester.tap(find.text('Arrival'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Scene 2');
      await tester.pump();
      expect(find.text('Arrival'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Arrival'), findsNothing);
      expect(find.text('Elsewhere'), findsNothing);
      expect(find.text('Scene 2'), findsNWidgets(2)); // 搜索输入与资源标题。
      await tester.tap(find.text('Scene 2').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await db.canvasDao
            .watchNodesByCanvas(canvasId)
            .firstWhere((nodes) => nodes.length == 2)
            .timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      final nodes = await tester.runAsync(
        () => db.canvasDao.getNodesByCanvas(canvasId),
      );
      expect(nodes!.map((n) => n.refId), contains(unnamed));
      final added = nodes.singleWhere((n) => n.refId == unnamed);
      expect((added.x, added.y), (56, 44));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

Widget _wrap(Widget child) => EasyLocalization(
  supportedLocales: const [Locale('en')],
  path: 'assets/translations',
  assetLoader: const MergingAssetLoader(),
  fallbackLocale: const Locale('en'),
  startLocale: const Locale('en'),
  child: Builder(
    builder: (context) => MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: RevericThemeData.reveric.toThemeData(),
      builder: (context, child) =>
          RevericTheme(data: RevericThemeData.reveric, child: child!),
      home: Scaffold(body: child),
    ),
  ),
);

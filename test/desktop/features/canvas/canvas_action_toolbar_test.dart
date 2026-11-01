// 职责: 验证画布工具条、重排后的视口定位与节点交互入口。
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/canvas/widgets/canvas_region.dart

import 'dart:async';

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reveric/desktop/features/canvas/edit_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_board.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_detail_layer.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_ai_focus_layer.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_flow_adapter.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_region.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/shared/providers/canvas_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/canvas_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/app_background.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'UI layouts fit saved positions before the display stream catches up; ordinary edits preserve the viewport',
    (tester) async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      addTearDown(db.close);
      final service = CanvasService(db);
      late String canvasId;
      late ({List<CanvasNode> nodes, List<CanvasEdge> edges}) content;
      await tester.runAsync(() async {
        canvasId = await service.createCanvas(name: 'Viewport');
        String? previous;
        for (var i = 0; i < 3; i++) {
          final id = await service.addNode(
            canvasId: canvasId,
            type: canvasNodeTypeSticky,
            title: 'Node $i',
            content: 'Body $i',
            x: 12000 + i * 400,
            y: 0,
          );
          if (previous != null) {
            await service.addEdge(
              canvasId: canvasId,
              sourceNodeId: previous,
              targetNodeId: id,
              type: canvasEdgeTypeTimeline,
            );
          }
          previous = id;
        }
        content = await service.watchCanvasContent(canvasId).first;
      });
      final display =
          StreamController<
            ({List<CanvasNode> nodes, List<CanvasEdge> edges})
          >();
      addTearDown(display.close);
      display.add(content);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            novelContentDatabaseProvider('viewport_test').overrideWithValue(db),
            appBackgroundActiveProvider.overrideWithValue(false),

            canvasContentStreamProvider((
              canvasId: canvasId,
              databasePath: 'viewport_test',
            )).overrideWith((ref) => display.stream),
          ],
          child: _wrap(
            CanvasRegion(canvasId: canvasId, databasePath: 'viewport_test'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester
          .widget<CanvasBoard>(find.byType(CanvasBoard))
          .controller;
      for (final mode in [
        canvasLayoutTreeTb,
        canvasLayoutGrid,
        canvasLayoutTreeLr,
        canvasLayoutAuto,
        canvasLayoutAuto,
      ]) {
        controller.setViewport(const flow.GraphViewport(x: -12000, y: 200));
        final layout = tester
            .widget<CanvasBoard>(find.byType(CanvasBoard))
            .onLayout!;
        var completed = false;
        final operation = layout(mode).whenComplete(() => completed = true);
        for (var i = 0; i < 100 && !completed; i++) {
          await tester.pump(const Duration(milliseconds: 10));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(completed, isTrue, reason: 'layout must finish');
        await operation;
        content = (
          nodes: await db.canvasDao.getNodesByCanvas(canvasId),
          edges: await db.canvasDao.getEdgesByCanvas(canvasId),
        );
        // 保存已完成，但模拟 UI 的订阅尚未送达新坐标。
        display.add(content);
        await tester.pumpAndSettle();
        expect(controller.nodes.length, 3);
        expect(controller.connections.length, 2);
        for (final node in content.nodes) {
          expect(
            controller.viewportExtent.rect.contains(canvasNodeCenter(node)),
            isTrue,
            reason: '$mode must bring ${node.id} back into the viewport',
          );
          expect(controller.getNode(node.id)!.data.node.content, node.content);
        }
      }
      controller.panBy(const flow.ScreenOffset(Offset(37, 29)));
      final viewport = controller.viewport;
      // 正文保存、拖拽落点同样触发重载，但不能跟着重排的修复重置视角。
      for (final changed in [
        content.nodes.first.copyWith(content: 'Edited body'),
        content.nodes.first.copyWith(x: content.nodes.first.x + 80),
      ]) {
        display.add((
          nodes: [changed, ...content.nodes.skip(1)],
          edges: content.edges,
        ));
        await tester.pumpAndSettle();
        expect(controller.viewport, viewport);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'same host switching canvases initializes controller and delivers drag and resize events',
    (tester) async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      addTearDown(db.close);
      final sessions = [CanvasEditSession(), CanvasEditSession()];
      final controllers = [
        for (final session in sessions)
          CanvasFlowController(
            config: flow.NodeFlowConfig(
              plugins: [...flow.NodeFlowConfig.defaultPlugins(), session],
            ),
          ),
      ];
      final active = ValueNotifier(0);
      final detailLayer = CanvasDetailLayer();
      final focusLayer = CanvasAiFocusLayer();
      await tester.runAsync(() async {
        for (final id in ['first', 'second']) {
          await db.canvasDao.upsertNode(
            _stickyNode().copyWith(id: 'node_$id', canvasId: id),
          );
        }
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            novelContentDatabaseProvider('test_path').overrideWithValue(db),
            for (final id in ['first', 'second'])
              canvasContentStreamProvider((
                canvasId: id,
                databasePath: 'test_path',
              )).overrideWith(
                (ref) => Stream.value((
                  nodes: [_stickyNode().copyWith(id: 'node_$id', canvasId: id)],
                  edges: const <CanvasEdge>[],
                )),
              ),
          ],
          child: _wrap(
            ValueListenableBuilder<int>(
              valueListenable: active,
              builder: (context, index, _) => CanvasBoard(
                canvasId: index == 0 ? 'first' : 'second',
                databasePath: 'test_path',
                controller: controllers[index],
                detailLayer: detailLayer,
                focusLayer: focusLayer,
                editSession: sessions[index],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final host = tester.element(find.byType(CanvasBoard));
      active.value = 1;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.element(find.byType(CanvasBoard)), same(host));
      final controller = controllers.last;
      final session = sessions.last;
      final node = controller.getNode('node_second')!;
      expect(controller.isEditorInitialized, isTrue);
      controller.startNodeDrag(node.id);
      expect(session.hasInteractions, isTrue);
      expect(sessions.first.hasInteractions, isFalse);
      controller.moveNodeDrag(const Offset(40, 20));
      final dragged = node.position.value;
      controller.endNodeDrag();
      await session.flushAndWait();
      expect(session.hasInteractions, isFalse);
      final afterDrag = (await db.canvasDao.getNodeById(node.id))!;
      expect(Offset(afterDrag.x, afterDrag.y), dragged);
      final oldSize = node.size.value;
      controller.startResize(
        node.id,
        flow.ResizeHandle.bottomRight,
        const Offset(300, 300),
      );
      expect(session.hasInteractions, isTrue);
      controller.updateResize(const Offset(340, 340));
      expect(node.size.value, isNot(oldSize));
      controller.endResize();
      await session.flushAndWait();
      final afterResize = (await db.canvasDao.getNodeById(node.id))!;
      expect(Size(afterResize.width!, afterResize.height!), node.size.value);
      expect(session.hasInteractions, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      active.dispose();
      for (final controller in controllers) {
        controller.dispose();
      }
      for (final session in sessions) {
        session.dispose();
      }
    },
  );

  testWidgets('工具条按钮可点击且节点右侧端口可开始手动连线', (tester) async {
    var addRefCalled = 0;
    var addStickyCalled = 0;
    var autoLayoutCalled = 0;

    final db = NovelContentDatabase.forTest(NativeDatabase.memory());
    addTearDown(db.close);
    final controller = CanvasFlowController();
    final detailLayer = CanvasDetailLayer();
    final focusLayer = CanvasAiFocusLayer();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelContentDatabaseProvider('test_path').overrideWithValue(db),
          canvasContentStreamProvider((
            canvasId: 'test_canvas',
            databasePath: 'test_path',
          )).overrideWith(
            (ref) => Stream.value((
              nodes: [_stickyNode()],
              edges: const <CanvasEdge>[],
            )),
          ),
          canvasInvalidNodeIdsProvider((
            canvasId: 'test_canvas',
            databasePath: 'test_path',
          )).overrideWith((ref) => const <String>{}),
        ],
        child: _wrap(
          SizedBox(
            width: 1000,
            height: 800,
            child: CanvasBoard(
              canvasId: 'test_canvas',
              databasePath: 'test_path',
              controller: controller,
              detailLayer: detailLayer,
              focusLayer: focusLayer,
              onAddReference: () => addRefCalled++,
              onAddSticky: () => addStickyCalled++,
              onAutoLayout: () => autoLayoutCalled++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 找到三个按钮并点击
    final addRefFinder = find.byTooltip('引用');
    final addStickyFinder = find.byTooltip('添加便签');
    final autoLayoutFinder = find.byTooltip('按连线关系重排节点，手动摆过的节点不动');

    expect(addRefFinder, findsOneWidget);
    expect(addStickyFinder, findsOneWidget);
    expect(autoLayoutFinder, findsOneWidget);

    await tester.tap(addRefFinder);
    await tester.pump();
    expect(addRefCalled, 1);

    await tester.tap(addStickyFinder);
    await tester.pump();
    expect(addStickyCalled, 1);

    await tester.tap(autoLayoutFinder);
    await tester.pump();
    expect(autoLayoutCalled, 1);

    final sourcePort = find.byWidgetPredicate(
      (widget) =>
          widget is flow.PortWidget<CanvasFlowNodeData> &&
          widget.nodeId == 'sticky_source' &&
          widget.port.id == canvasAnchorRightPortId,
      description: '便签右侧可交互连线端口',
    );
    expect(sourcePort, findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(sourcePort),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    expect(controller.isConnecting, isTrue);

    await gesture.cancel();
    await tester.pump();
    expect(controller.isConnecting, isFalse);

    // 清理 widget 树，避免 postFrameCallback 在 ProviderScope 销毁后触发
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

CanvasNode _stickyNode() {
  final now = DateTime(2026, 1, 1);
  return CanvasNode(
    id: 'sticky_source',
    canvasId: 'test_canvas',
    type: canvasNodeTypeSticky,
    title: '',
    content: '',
    x: 120,
    y: 240,
    width: canvasStickyDefaultWidth,
    height: canvasStickyDefaultHeight,
    zIndex: 0,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Widget _wrap(Widget child) {
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
            child: Scaffold(body: child),
          ),
        );
      },
    ),
  );
}

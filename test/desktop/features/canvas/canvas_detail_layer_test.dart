// 职责: 验证画布详情浮层拦截输入点击，避免清除正在编辑便签的选中态
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_detail_layer.dart
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart

import 'package:easy_localization/easy_localization.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/edit_session.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_detail_layer.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_flow_adapter.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'edge label refresh preserves selection, draft and composing input',
    (tester) async {
      final session = CanvasEditSession();
      final layer = CanvasDetailLayer();
      final controller = CanvasFlowController();
      final nodes = [
        for (var i = 0; i < 2; i++)
          CanvasNode(
            id: 'n$i',
            canvasId: 'canvas',
            type: canvasNodeTypeSticky,
            title: '',
            content: '',
            x: 40 + i * 380,
            y: 40,
            zIndex: 0,
            sortOrder: i,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            deletedAt: notDeletedSentinel,
          ),
      ];
      final edge = ValueNotifier(
        CanvasEdge(
          id: 'edge',
          canvasId: 'canvas',
          sourceNodeId: 'n0',
          targetNodeId: 'n1',
          type: canvasEdgeTypeTimeline,
          label: '连线中间选区',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      for (final node in nodes) {
        controller.addNode(
          canvasNodeToFlowNode(node, colors: RevericThemeData.reveric.colors),
        );
      }
      controller.addConnection(
        canvasEdgeToFlowConnection(
          edge.value,
          colors: RevericThemeData.reveric.colors,
        ),
      );
      layer.callbacks = CanvasDetailCallbacks(
        onSelectNode: controller.selectNode,
        onDeleteNode: (_) {},
        onStickyTitleChanged: (_, _) async {},
        onStickyContentChanged: (_, _) async {},
        onNodeColorChanged: (_, _) {},
        onEdgeTypeChanged: (_, _) {},
        onEdgeLabelChanged: (_, _) async {},
        onDeleteEdge: (_) {},
        onClearSelection: controller.clearSelection,
        onPickPendingEdgeType: (_) {},
        onCancelPendingEdge: () {},
        editSession: session,
      );
      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<CanvasEdge>(
            valueListenable: edge,
            builder: (context, value, _) {
              layer.content = (nodes: nodes, edges: [value]);
              return Stack(
                children: [
                  flow.NodeFlowEditor<CanvasFlowNodeData, String>(
                    controller: controller,
                    theme: flow.NodeFlowTheme.light,
                    nodeBuilder: (_, _) => const SizedBox.expand(),
                  ),
                  layer.buildOverlay(controller),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.selectConnection('edge');
      await tester.pump();
      final finder = find.byType(TextField);
      await tester.tap(finder);
      final input = tester.widget<TextField>(finder).controller!;
      input.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
      final focus = FocusManager.instance.primaryFocus;
      edge.value = edge.value.copyWith(type: canvasEdgeTypeCausal);
      await tester.pump();
      expect(input.text, '连线中间选区');
      expect(
        input.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(FocusManager.instance.primaryFocus, same(focus));
      edge.value = edge.value.copyWith(label: const Value('短文'));
      await tester.pump();
      expect(input.text, '短文');
      expect(
        input.selection,
        const TextSelection(baseOffset: 1, extentOffset: 2),
      );
      expect(FocusManager.instance.primaryFocus, same(focus));
      input.value = const TextEditingValue(
        text: '草稿组词',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 2, end: 4),
      );
      edge.value = edge.value.copyWith(label: const Value('external'));
      await tester.pump();
      expect(input.value.composing, const TextRange(start: 2, end: 4));
      expect(input.text, '草稿组词');
      await expectLater(
        session.flushAndWait(),
        throwsA(isA<CanvasEditSessionException>()),
      );
      input.value = const TextEditingValue(
        text: 'local draft',
        selection: TextSelection.collapsed(offset: 3),
      );
      edge.value = edge.value.copyWith(label: const Value('external again'));
      await tester.pump();
      expect(input.text, 'local draft');
      expect(input.selection, const TextSelection.collapsed(offset: 3));
      await session.flushAndWait();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
      session.dispose();
      edge.dispose();
    },
  );

  testWidgets('点击便签输入框不会清除节点选中态', (tester) async {
    final detailLayer = CanvasDetailLayer();
    final controller = CanvasFlowController();
    final node = CanvasNode(
      id: 'sticky_1',
      canvasId: 'canvas_1',
      type: canvasNodeTypeSticky,
      refType: null,
      refId: null,
      title: '',
      content: '',
      x: 48,
      y: 48,
      width: null,
      height: null,
      style: null,
      zIndex: 0,
      sortOrder: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      deletedAt: notDeletedSentinel,
    );
    controller.addNode(
      canvasNodeToFlowNode(node, colors: RevericThemeData.reveric.colors),
    );
    detailLayer
      ..callbacks = CanvasDetailCallbacks(
        onSelectNode: controller.selectNode,
        onDeleteNode: (_) {},
        onStickyTitleChanged: (_, _) async {},
        onStickyContentChanged: (_, _) async {},
        onNodeColorChanged: (_, _) {},
        onEdgeTypeChanged: (_, _) {},
        onEdgeLabelChanged: (_, _) async {},
        onDeleteEdge: (_) {},
        onClearSelection: controller.clearSelection,
        onPickPendingEdgeType: (_) {},
        onCancelPendingEdge: () {},
      )
      ..content = (nodes: [node], edges: const <CanvasEdge>[]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 720,
          height: 560,
          child: Stack(
            children: [
              flow.NodeFlowEditor<CanvasFlowNodeData, String>(
                controller: controller,
                theme: flow.NodeFlowTheme.light,
                nodeBuilder: (_, _) => const SizedBox.expand(),
              ),
              detailLayer.buildOverlay(controller),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    controller.selectNode(node.id);
    await tester.pump();

    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    expect(controller.selectedNodeIds, contains(node.id));
    expect(find.byType(TextField), findsNWidgets(2));
  });
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

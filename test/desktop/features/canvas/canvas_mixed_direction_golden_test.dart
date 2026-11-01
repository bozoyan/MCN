// 职责: 画布多方向连线 golden 测试 — 验证垂直/斜向连接也采用边界落点
// 关联文件:
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
//   lib/desktop/features/canvas/widgets/canvas_node_widget.dart

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/canvas_palette.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_flow_adapter.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_node_widget.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await _loadFont('LXGWWenKai', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Georgia', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Literata', 'assets/fonts/Literata-Regular.ttf');
  });

  testWidgets('golden: mixed-direction nodes with boundary ports', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final colors = RevericThemeData.reveric.colors;

    // 网格摆位，同 canvas_connection_golden_test：贴边排布看不出连线落点对不对。
    const origin = Offset(40, 40);
    Offset cell(int col, int row) => origin + canvasGridOrigin(col, row);
    final startPosition =
        cell(0, 0) +
        const Offset(
          0,
          (canvasStickyDefaultHeight - canvasReferenceDefaultHeight) / 2,
        );
    // 分支节点挂在 beat1 正下方一行，用来验证垂直方向选的是 bottom→top port。
    final branchPosition =
        cell(2, 1) +
        const Offset(
          (canvasStickyDefaultWidth - canvasReferenceDefaultWidth) / 2,
          0,
        );

    final nodes = [
      _referenceNode(
        id: 'node_start',
        title: '穿越之始',
        refType: entityTypeChapter,
        position: startPosition,
      ),
      _stickyNode(
        id: 'node_beat0',
        title: 'Beat 0 穿越降临',
        content: '【穿越降临】第1-5章\n林默穿越回2015，确认时间锚点',
        position: cell(1, 0),
      ),
      _stickyNode(
        id: 'node_beat1',
        title: 'Beat 1 找到盟友',
        content: '【找到盟友】第6-10章\n遇见苏瑶，用未来AI理念打动她',
        position: cell(2, 0),
      ),
      _referenceNode(
        id: 'node_branch',
        title: '伏笔分支',
        refType: entityTypeForeshadowing,
        position: branchPosition,
      ),
    ];

    final edges = [
      _edge(
        id: 'edge_0',
        source: 'node_start',
        target: 'node_beat0',
        sourcePosition: startPosition,
        targetPosition: cell(1, 0),
        targetSize: canvasStickyDefaultSize,
      ),
      _edge(
        id: 'edge_1',
        source: 'node_beat0',
        target: 'node_beat1',
        sourcePosition: cell(1, 0),
        targetPosition: cell(2, 0),
        sourceSize: canvasStickyDefaultSize,
        targetSize: canvasStickyDefaultSize,
      ),
      _edge(
        id: 'edge_vertical',
        source: 'node_beat1',
        target: 'node_branch',
        sourcePosition: cell(2, 0),
        targetPosition: branchPosition,
        sourceSize: canvasStickyDefaultSize,
      ),
    ];

    final controller = flow.NodeFlowController<CanvasFlowNodeData, String>(
      config: flow.NodeFlowConfig(
        minZoom: 0.2,
        maxZoom: 3.0,
        showAttribution: false,
      ),
      initialViewport: const flow.GraphViewport(x: 0, y: 0, zoom: 1),
      nodes: nodes,
      connections: edges,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        SizedBox.expand(
          child: flow.NodeFlowEditor<CanvasFlowNodeData, String>(
            controller: controller,
            theme: canvasFlowTheme(
              colors,
              RevericThemeData.reveric.typography,
              false,
              fontFamily: 'LXGWWenKai',
            ),
            behavior: flow.NodeFlowBehavior.design,
            nodeBuilder: (context, node) => CanvasNodeCard(node: node),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/canvas_mixed_direction_connections.png'),
    );
  });
}

CanvasFlowNode _referenceNode({
  required String id,
  required String title,
  required String refType,
  required Offset position,
}) {
  return canvasNodeToFlowNode(
    CanvasNode(
      id: id,
      canvasId: 'canvas_golden',
      type: canvasNodeTypeReference,
      refType: refType,
      refId: 'ref_$id',
      title: title,
      content: '',
      x: position.dx,
      y: position.dy,
      width: null,
      height: null,
      zIndex: 0,
      sortOrder: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      deletedAt: notDeletedSentinel,
    ),
    colors: RevericThemeData.reveric.colors,
  );
}

CanvasFlowNode _stickyNode({
  required String id,
  required String title,
  required String content,
  required Offset position,
}) {
  return canvasNodeToFlowNode(
    CanvasNode(
      id: id,
      canvasId: 'canvas_golden',
      type: canvasNodeTypeSticky,
      title: title,
      content: content,
      x: position.dx,
      y: position.dy,
      width: null,
      height: null,
      zIndex: 0,
      sortOrder: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      deletedAt: notDeletedSentinel,
    ),
    colors: RevericThemeData.reveric.colors,
  );
}

CanvasFlowConnection _edge({
  required String id,
  required String source,
  required String target,
  required Offset sourcePosition,
  required Offset targetPosition,
  Size sourceSize = canvasReferenceNodeSize,
  Size targetSize = canvasReferenceNodeSize,
}) {
  final sourceCenter =
      sourcePosition + Offset(sourceSize.width / 2, sourceSize.height / 2);
  final targetCenter =
      targetPosition + Offset(targetSize.width / 2, targetSize.height / 2);
  return canvasEdgeToFlowConnection(
    CanvasEdge(
      id: id,
      canvasId: 'canvas_golden',
      sourceNodeId: source,
      targetNodeId: target,
      type: canvasEdgeTypeTimeline,
      label: null,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    colors: RevericThemeData.reveric.colors,
    sourceCenter: sourceCenter,
    targetCenter: targetCenter,
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
          debugShowCheckedModeBanner: false,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(
            fontFamily: 'LXGWWenKai',
          ),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(
              backgroundColor: RevericThemeData.reveric.colors.canvas,
              body: child,
            ),
          ),
        );
      },
    ),
  );
}

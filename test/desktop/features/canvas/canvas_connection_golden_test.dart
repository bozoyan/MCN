// 职责: 画布连线 golden 测试 — 渲染带连线的完整 NodeFlowEditor,确认连线落点是否符合阅读方向
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
//   lib/desktop/features/canvas/widgets/canvas_node_widget.dart
//   lib/desktop/features/canvas/canvas_palette.dart

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
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
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

  testWidgets('golden: timeline nodes with connections', (tester) async {
    tester.view.physicalSize = const Size(1700, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final colors = RevericThemeData.reveric.colors;

    // 网格摆位(与 AI 工具落库时同一套算法)：同行相邻两格留 canvasGridGapX 的
    // 空隙，连线才有落笔的地方。之前 fixture 按 280 排(刚好贴边)，即使连线画对
    // 了也全被卡片盖住。
    const origin = Offset(40, 60);
    Offset cell(int col, int row) => origin + canvasGridOrigin(col, row);
    // 引用节点比便签矮，对齐到便签行的垂直中线才不显得吊在上面。
    final startPosition =
        cell(0, 0) +
        const Offset(
          0,
          (canvasStickyDefaultHeight - canvasReferenceDefaultHeight) / 2,
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
      _stickyNode(
        id: 'node_beat2',
        title: 'Beat 2 首个成果',
        content: '【首个成果】第11-15章\n原型完成，苏瑶关键算法突破',
        position: cell(3, 0),
      ),
    ];

    final edges = [
      _edge(
        id: 'edge_0',
        source: 'node_start',
        target: 'node_beat0',
        label: '第1章启动',
        sourcePosition: startPosition,
        targetPosition: cell(1, 0),
        targetSize: canvasStickyDefaultSize,
      ),
      _edge(
        id: 'edge_1',
        source: 'node_beat0',
        target: 'node_beat1',
        label: '第6章起',
        sourcePosition: cell(1, 0),
        targetPosition: cell(2, 0),
        sourceSize: canvasStickyDefaultSize,
        targetSize: canvasStickyDefaultSize,
      ),
      _edge(
        id: 'edge_2',
        source: 'node_beat1',
        target: 'node_beat2',
        label: '第11章起',
        sourcePosition: cell(2, 0),
        targetPosition: cell(3, 0),
        sourceSize: canvasStickyDefaultSize,
        targetSize: canvasStickyDefaultSize,
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
      matchesGoldenFile('goldens/canvas_timeline_connections.png'),
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
  String? label,
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
      label: label,
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

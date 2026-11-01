// 职责: 选中节点出边流动高亮测试 — 守住「只动出边、取消即还原、不抢别的动效」
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_edge_flow_highlight.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_edge_flow_highlight.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_edge_grow_effect.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_flow_adapter.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart';

const _canvasId = 'canvas_edge_highlight_test';
const _accent = Color(0xFFA78BFA);

({List<CanvasNode> nodes, List<CanvasEdge> edges}) _buildContent() {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  CanvasNode node(String id, double x) => CanvasNode(
    id: id,
    canvasId: _canvasId,
    type: canvasNodeTypeSticky,
    title: id,
    content: '',
    x: x,
    y: 0,
    zIndex: 0,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
  CanvasEdge edge(String id, String source, String target) => CanvasEdge(
    id: id,
    canvasId: _canvasId,
    sourceNodeId: source,
    targetNodeId: target,
    type: canvasEdgeTypeCausal,
    createdAt: now,
    updatedAt: now,
  );
  return (
    nodes: [node('a', 0), node('b', 400), node('c', 800)],
    edges: [edge('a_b', 'a', 'b'), edge('c_a', 'c', 'a')],
  );
}

CanvasFlowController _buildController() {
  final content = _buildContent();
  final controller = CanvasFlowController();
  controller.loadGraph(
    canvasContentToFlowGraph(
      content.nodes,
      content.edges,
      colors: RevericThemeData.reveric.colors,
    ),
  );
  return controller;
}

void main() {
  late CanvasFlowController controller;
  late CanvasEdgeFlowHighlight highlight;

  setUp(() {
    controller = _buildController();
    highlight = CanvasEdgeFlowHighlight(color: _accent);
  });

  test('选中节点只让出边流动，入边不动', () {
    final outgoing = controller.getConnection('a_b')!;
    final incoming = controller.getConnection('c_a')!;
    final incomingColor = incoming.color;

    controller.selectNode('a');
    highlight.sync(controller);

    expect(outgoing.animationEffect, isA<FlowingDashEffect>());
    expect(outgoing.color, _accent);
    expect(outgoing.endPoint!.color, _accent);
    expect(incoming.animationEffect, isNull);
    expect(incoming.color, incomingColor);
  });

  test('取消选中后还原颜色、箭头并摘掉 effect', () {
    final outgoing = controller.getConnection('a_b')!;
    final originalColor = outgoing.color;
    final originalEndPoint = outgoing.endPoint;

    controller.selectNode('a');
    highlight.sync(controller);
    controller.clearSelection();
    highlight.sync(controller);

    expect(outgoing.animationEffect, isNull);
    expect(outgoing.color, originalColor);
    expect(outgoing.endPoint, originalEndPoint);
  });

  test('别的动效占着的边不抢', () {
    final outgoing = controller.getConnection('a_b')!;
    final grow = CanvasEdgeGrowEffect();
    outgoing.animationEffect = grow;
    final originalColor = outgoing.color;

    controller.selectNode('a');
    highlight.sync(controller);

    expect(outgoing.animationEffect, same(grow));
    expect(outgoing.color, originalColor);
  });

  test('整图重载后不把旧还原值写到新连线上', () {
    controller.selectNode('a');
    highlight.sync(controller);

    final content = _buildContent();
    controller.loadGraph(
      canvasContentToFlowGraph(
        content.nodes,
        content.edges,
        colors: RevericThemeData.reveric.colors,
      ),
    );
    final reloaded = controller.getConnection('a_b')!;
    final reloadedColor = reloaded.color;
    highlight.sync(controller);

    expect(reloaded.animationEffect, isNull);
    expect(reloaded.color, reloadedColor);
  });
}

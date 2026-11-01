// 职责: Canvas Flow Adapter 测试 — 验证 DB↔flow 双向转换逻辑(节点类型、anchor port、边过滤、位置回写、边视觉语义)
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/shared/database/novel_content_database.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart';
import 'package:reveric/desktop/features/canvas/canvas_palette.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_flow_adapter.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/shared/models/canvas_tree_layout.dart';
import 'package:reveric/shared/components/waypoint_connection_style.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  group('canvasNodeToFlowNode', () {
    test('sticky node creates CommentNode with anchor port and text', () {
      final node = _stickyNode(id: 'sticky_1', content: 'hello world');
      final flowNode = canvasNodeToFlowNode(node, colors: _colors);

      expect(flowNode, isA<CanvasStickyNode>());
      expect(flowNode.id, 'sticky_1');
      expect(flowNode.type, canvasNodeTypeSticky);
      // 便签正文留在 data 的 DB 快照里,由 nodeBuilder 渲染。
      expect(flowNode.data.node.content, 'hello world');
      // anchor port 挂载后可连线（top/right/bottom/left 四向）
      expect(
        flowNode.ports.any((p) => p.id == canvasAnchorRightPortId),
        isTrue,
      );
      expect(flowNode.ports.any((p) => p.id == canvasAnchorLeftPortId), isTrue);
      expect(flowNode.ports.any((p) => p.id == canvasAnchorTopPortId), isTrue);
      expect(
        flowNode.ports.any((p) => p.id == canvasAnchorBottomPortId),
        isTrue,
      );
      expect(flowNode.ports.length, 4);
      // 位置保留
      expect(flowNode.position.value, const Offset(120, 240));
    });

    test('sticky node uses default size when width/height null', () {
      final node = _stickyNode(
        id: 'sticky_2',
        content: 'x',
        width: null,
        height: null,
      );
      final flowNode = canvasNodeToFlowNode(node, colors: _colors);

      expect(flowNode.size.value.width, canvasStickyDefaultWidth);
      expect(flowNode.size.value.height, canvasStickyDefaultHeight);
    });

    test('sticky node is resizable and clamps programmatic sizes', () {
      final node = _stickyNode(id: 'sticky_3', content: 'x');
      final flowNode = canvasNodeToFlowNode(node, colors: _colors);

      // 便签可拖拽 resize；引用节点尺寸固定。
      expect(flowNode.isResizable, isTrue);

      // DB 里的异常尺寸(或旧数据)不应直接生效,须落在 min/max 内。
      flowNode.setSize(const Size(10, 10));
      expect(flowNode.size.value, canvasStickyMinSize);
      flowNode.setSize(const Size(9999, 9999));
      expect(flowNode.size.value, canvasStickyMaxSize);
    });

    test('reference node creates Node with anchor port, position and size', () {
      final node = _referenceNode(
        id: 'ref_1',
        refType: entityTypeCharacter,
        title: 'Alice',
      );
      final flowNode = canvasNodeToFlowNode(node, colors: _colors);

      expect(flowNode, isA<CanvasFlowNode>());
      expect(flowNode.id, 'ref_1');
      expect(flowNode.type, canvasNodeTypeReference);
      expect(
        flowNode.ports.any((p) => p.id == canvasAnchorRightPortId),
        isTrue,
      );
      expect(flowNode.ports.any((p) => p.id == canvasAnchorLeftPortId), isTrue);
      expect(flowNode.ports.any((p) => p.id == canvasAnchorTopPortId), isTrue);
      expect(
        flowNode.ports.any((p) => p.id == canvasAnchorBottomPortId),
        isTrue,
      );
      expect(flowNode.ports.length, 4);
      expect(flowNode.position.value, const Offset(50, 60));
      // 引用型默认尺寸
      expect(flowNode.size.value, canvasReferenceNodeSize);
      // data 携带原始 DB 节点
      expect(flowNode.data.node.id, 'ref_1');
    });

    test('reference node uses custom width/height when provided', () {
      final node = _referenceNode(
        id: 'ref_2',
        refType: entityTypeChapter,
        title: 'Ch1',
        width: 300,
        height: 80,
      );
      final flowNode = canvasNodeToFlowNode(node, colors: _colors);

      expect(flowNode.size.value, const Size(300, 80));
    });

    test('invalid reference node carries isInvalid=true in data', () {
      final node = _referenceNode(
        id: 'ref_bad',
        refType: entityTypeCharacter,
        title: '',
      );
      final flowNode = canvasNodeToFlowNode(
        node,
        colors: _colors,
        isInvalid: true,
      );

      expect(flowNode.data.isInvalid, isTrue);
    });
  });

  // 回归：flow 库对无 NodeShape 的矩形节点，把 port 在「垂直于所在边」方向上的
  // 位置完全取自 Port.offset。offset 缺省为 zero 时连接点落到节点角上，连线缩成
  // 一个小钩(整张画布看不到任何连线)。这里锁住居中量。
  group('anchor port offsets', () {
    test('left/right ports center vertically on the node', () {
      final flowNode = canvasNodeToFlowNode(
        _stickyNode(id: 'sticky_ports', content: 'x'),
        colors: _colors,
      );
      final halfHeight = flowNode.size.value.height / 2;

      for (final id in [canvasAnchorLeftPortId, canvasAnchorRightPortId]) {
        expect(
          flowNode.ports.firstWhere((p) => p.id == id).offset,
          Offset(0, halfHeight),
          reason: '$id 应落在左右边中点',
        );
      }
    });

    test('top/bottom ports center horizontally on the node', () {
      final flowNode = canvasNodeToFlowNode(
        _referenceNode(id: 'ref_ports', refType: entityTypeChapter, title: 'C'),
        colors: _colors,
      );
      final halfWidth = flowNode.size.value.width / 2;

      for (final id in [canvasAnchorTopPortId, canvasAnchorBottomPortId]) {
        expect(
          flowNode.ports.firstWhere((p) => p.id == id).offset,
          Offset(halfWidth, 0),
          reason: '$id 应落在上下边中点',
        );
      }
    });

    test('resize keeps port offsets on the new edge midpoints', () {
      final flowNode = canvasNodeToFlowNode(
        _stickyNode(id: 'sticky_resize', content: 'x'),
        colors: _colors,
      );

      flowNode.setSize(const Size(360, 240));

      expect(
        flowNode.ports
            .firstWhere((p) => p.id == canvasAnchorRightPortId)
            .offset,
        const Offset(0, 120),
      );
      expect(
        flowNode.ports
            .firstWhere((p) => p.id == canvasAnchorBottomPortId)
            .offset,
        const Offset(180, 0),
      );
    });
  });

  group('canvasEdgeToFlowConnection', () {
    test('tree layouts keep fork and merge ports on the reading axis', () {
      for (final layout in [canvasLayoutTreeTb, canvasLayoutTreeLr]) {
        for (final crossOffset in [-720.0, 720.0]) {
          final vertical = layout == canvasLayoutTreeTb;
          final start = const Offset(1000, 1000);
          final branch =
              start +
              (vertical ? Offset(crossOffset, 288) : Offset(400, crossOffset));
          final end =
              start + (vertical ? const Offset(0, 576) : const Offset(800, 0));
          for (final (source, target) in [(start, branch), (branch, end)]) {
            final connection = canvasEdgeToFlowConnection(
              _edge(id: 'branch', type: canvasEdgeTypeTimeline),
              colors: _colors,
              sourceCenter: source,
              targetCenter: target,
              layout: layout,
            );
            expect(
              connection.sourcePortId,
              vertical ? canvasAnchorBottomPortId : canvasAnchorRightPortId,
            );
            expect(
              connection.targetPortId,
              vertical ? canvasAnchorTopPortId : canvasAnchorLeftPortId,
            );
          }
        }
      }
    });
    test('defaults to right→left when no node centers provided', () {
      final edge = _edge(id: 'e1', type: canvasEdgeTypeRelationship);
      final conn = canvasEdgeToFlowConnection(edge, colors: _colors);

      expect(conn.id, 'e1');
      expect(conn.sourcePortId, canvasAnchorRightPortId);
      expect(conn.targetPortId, canvasAnchorLeftPortId);
      expect(conn.data, canvasEdgeTypeRelationship);
    });

    test('picks top/bottom ports for vertical relationship', () {
      final edge = _edge(id: 'e1v', type: canvasEdgeTypeRelationship);
      final conn = canvasEdgeToFlowConnection(
        edge,
        colors: _colors,
        sourceCenter: const Offset(100, 100),
        targetCenter: const Offset(100, 300),
      );

      expect(conn.sourcePortId, canvasAnchorBottomPortId);
      expect(conn.targetPortId, canvasAnchorTopPortId);
    });

    test('picks left/right ports for horizontal relationship', () {
      final edge = _edge(id: 'e1h', type: canvasEdgeTypeRelationship);
      final conn = canvasEdgeToFlowConnection(
        edge,
        colors: _colors,
        sourceCenter: const Offset(100, 100),
        targetCenter: const Offset(300, 100),
      );

      expect(conn.sourcePortId, canvasAnchorRightPortId);
      expect(conn.targetPortId, canvasAnchorLeftPortId);
    });

    test('passes label as ConnectionLabel when non-empty', () {
      final edge = _edge(
        id: 'e2',
        type: canvasEdgeTypeCausal,
        label: 'because',
      );
      final conn = canvasEdgeToFlowConnection(edge, colors: _colors);

      expect(conn.label?.text, 'because');
    });

    test('omits label when null or empty', () {
      final edgeNull = _edge(
        id: 'e3',
        type: canvasEdgeTypeTimeline,
        label: null,
      );
      final edgeEmpty = _edge(
        id: 'e4',
        type: canvasEdgeTypeTimeline,
        label: '',
      );

      expect(
        canvasEdgeToFlowConnection(edgeNull, colors: _colors).label,
        isNull,
      );
      expect(
        canvasEdgeToFlowConnection(edgeEmpty, colors: _colors).label,
        isNull,
      );
    });

    test('assigns distinct colors per edge type', () {
      final types = canvasEdgeTypes;
      final colors = {
        for (final t in types)
          t: canvasEdgeToFlowConnection(
            _edge(id: 'c_$t', type: t),
            colors: _colors,
          ).color,
      };

      // 每种边类型都有非空颜色
      for (final t in types) {
        expect(colors[t], isNotNull, reason: '$t should have a color');
      }
      // 颜色互不相同
      expect(colors.values.toSet().length, types.length);
    });
  });

  group('canvasContentToFlowGraph', () {
    test('filters out edges referencing non-existent nodes', () {
      final nodes = [
        _referenceNode(id: 'n1', refType: entityTypeCharacter, title: 'A'),
        _referenceNode(id: 'n2', refType: entityTypeCharacter, title: 'B'),
      ];
      final edges = [
        _edge(
          id: 'valid',
          type: canvasEdgeTypeRelationship,
          source: 'n1',
          target: 'n2',
        ),
        _edge(
          id: 'orphan_src',
          type: canvasEdgeTypeCausal,
          source: 'ghost',
          target: 'n2',
        ),
        _edge(
          id: 'orphan_tgt',
          type: canvasEdgeTypeTimeline,
          source: 'n1',
          target: 'ghost',
        ),
      ];
      final graph = canvasContentToFlowGraph(nodes, edges, colors: _colors);

      expect(graph.nodes, hasLength(2));
      expect(graph.connections, hasLength(1));
      expect(graph.connections.single.id, 'valid');
    });

    test('marks invalid reference nodes via invalidNodeIds', () {
      final nodes = [
        _referenceNode(
          id: 'good',
          refType: entityTypeCharacter,
          title: 'Alice',
        ),
        _referenceNode(id: 'bad', refType: entityTypeCharacter, title: ''),
      ];
      final graph = canvasContentToFlowGraph(
        nodes,
        const [],
        colors: _colors,
        invalidNodeIds: {'bad'},
      );

      final goodNode = graph.nodes.singleWhere((n) => n.id == 'good');
      final badNode = graph.nodes.singleWhere((n) => n.id == 'bad');

      expect(goodNode.data.isInvalid, isFalse);
      expect(badNode.data.isInvalid, isTrue);
    });

    test('tree layout routes long directed edges until an endpoint moves', () {
      final ids = ['start', 'a', 'b', 'c', 'end'];
      final edges = [
        for (var i = 0; i < ids.length - 1; i++)
          _edge(
            id: 'e$i',
            type: canvasEdgeTypeTimeline,
            source: ids[i],
            target: ids[i + 1],
          ),
        _edge(
          id: 'long',
          type: canvasEdgeTypeCausal,
          source: 'a',
          target: 'end',
        ),
        _edge(
          id: 'related',
          type: canvasEdgeTypeRelationship,
          source: 'a',
          target: 'end',
        ),
      ];
      // 先让节点停在层级排列给出的位置上，和 service 落库后的状态一致。
      final arranged = resolveCanvasTreeLayout(
        nodes: [
          for (final id in ids)
            CanvasArrangeNode(
              id: id,
              sortOrder: 0,
              size: canvasStickyDefaultSize,
            ),
        ],
        edges: [
          for (final edge in edges)
            CanvasArrangeEdge(
              sourceNodeId: edge.sourceNodeId,
              targetNodeId: edge.targetNodeId,
              type: edge.type,
            ),
        ],
        direction: CanvasTreeDirection.top_to_bottom,
      );
      List<CanvasNode> nodesAt(Map<String, Offset> positions) => [
        for (final id in ids)
          _stickyNode(
            id: id,
            content: id,
            x: positions[id]!.dx,
            y: positions[id]!.dy,
          ),
      ];
      flow.ConnectionStyle? styleOf(CanvasFlowGraph graph, String id) =>
          graph.connections.singleWhere((c) => c.id == id).style;

      final graph = canvasContentToFlowGraph(
        nodesAt(arranged),
        edges,
        colors: _colors,
        layout: canvasLayoutTreeTb,
      );
      final style = styleOf(graph, 'long');
      expect(style, isA<WaypointConnectionStyle>());
      expect((style! as WaypointConnectionStyle).waypoints, hasLength(4));
      expect(styleOf(graph, 'e0'), isNull);
      expect(styleOf(graph, 'related'), isNull);
      expect(
        styleOf(
          canvasContentToFlowGraph(
            nodesAt(arranged),
            edges,
            colors: _colors,
            layout: canvasLayoutGrid,
          ),
          'long',
        ),
        isNull,
      );
      expect(
        styleOf(
          canvasContentToFlowGraph(
            nodesAt({
              ...arranged,
              'end': arranged['end']! + const Offset(40, 0),
            }),
            edges,
            colors: _colors,
            layout: canvasLayoutTreeTb,
          ),
          'long',
        ),
        isNull,
      );
    });

    test('empty input produces empty graph', () {
      final graph = canvasContentToFlowGraph(
        const [],
        const [],
        colors: _colors,
      );

      expect(graph.nodes, isEmpty);
      expect(graph.connections, isEmpty);
    });
  });

  group('flowNodeToCanvasNode', () {
    test('round-trips position and size back to CanvasNode', () {
      final original = _referenceNode(
        id: 'rt_1',
        refType: entityTypeLocation,
        title: 'Castle',
        width: 220,
        height: 70,
        x: 330,
        y: 440,
      );
      final flowNode = canvasNodeToFlowNode(original, colors: _colors);

      // 模拟拖拽：移动 flow 节点位置
      runInAction(() {
        flowNode.position.value = const Offset(999, 888);
      });
      // 模拟 resize：更新 flow 节点尺寸
      flowNode.setSize(const Size(150, 50));

      final roundTripped = flowNodeToCanvasNode(flowNode, previous: original);

      expect(roundTripped.x, 999);
      expect(roundTripped.y, 888);
      expect(roundTripped.width, 150);
      expect(roundTripped.height, 50);
      // 业务字段不变
      expect(roundTripped.title, 'Castle');
      expect(roundTripped.refType, entityTypeLocation);
      expect(roundTripped.id, 'rt_1');
    });

    test('preserves sticky node content when round-tripping geometry', () {
      final original = _stickyNode(
        id: 'rt_sticky',
        content: 'note text',
        x: 10,
        y: 20,
      );
      final flowNode = canvasNodeToFlowNode(original, colors: _colors);

      runInAction(() {
        flowNode.position.value = const Offset(500, 600);
      });

      final roundTripped = flowNodeToCanvasNode(flowNode, previous: original);

      expect(roundTripped.x, 500);
      expect(roundTripped.y, 600);
      expect(roundTripped.content, 'note text');
      expect(roundTripped.type, canvasNodeTypeSticky);
    });
  });

  group('canvasEdgeColor / dashPattern / directed', () {
    test('every edge type maps to a distinct color', () {
      final colors = {
        for (final t in canvasEdgeTypes) t: canvasEdgeColor(_colors, t),
      };

      // 5 类边必须一眼可分,同色即失去区分意义。
      expect(colors.values.toSet(), hasLength(canvasEdgeTypes.length));
    });

    test('falls back to association color for unknown type', () {
      expect(
        canvasEdgeColor(_colors, 'unknown'),
        canvasEdgeColor(_colors, canvasEdgeTypeAssociation),
      );
    });

    test('only foreshadow_payoff and association render dashed', () {
      // 语义偏弱的两类边在线型上也弱化,且两者线型互不相同。
      final foreshadow = canvasEdgeDashPattern(canvasEdgeTypeForeshadowPayoff);
      final association = canvasEdgeDashPattern(canvasEdgeTypeAssociation);

      expect(foreshadow, isNotNull);
      expect(association, isNotNull);
      expect(foreshadow, isNot(association));
      expect(canvasEdgeDashPattern(canvasEdgeTypeRelationship), isNull);
      expect(canvasEdgeDashPattern(canvasEdgeTypeCausal), isNull);
      expect(canvasEdgeDashPattern(canvasEdgeTypeTimeline), isNull);
    });

    test('only semantically ordered types draw an arrow head', () {
      // 因果/时间线/伏笔兑现的方向是信息本身;关系与关联是无向的。
      expect(canvasEdgeDirected(canvasEdgeTypeCausal), isTrue);
      expect(canvasEdgeDirected(canvasEdgeTypeTimeline), isTrue);
      expect(canvasEdgeDirected(canvasEdgeTypeForeshadowPayoff), isTrue);
      expect(canvasEdgeDirected(canvasEdgeTypeRelationship), isFalse);
      expect(canvasEdgeDirected(canvasEdgeTypeAssociation), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// 边色/纸色由主题 token 派生,测试固定一套预设即可。
const _colors = RevericColors.reveric;

CanvasNode _stickyNode({
  required String id,
  required String content,
  String title = '',
  double x = 120,
  double y = 240,
  double? width = canvasStickyDefaultWidth,
  double? height = canvasStickyDefaultHeight,
}) {
  return _canvasNode(
    id: id,
    type: canvasNodeTypeSticky,
    title: title,
    content: content,
    x: x,
    y: y,
    width: width,
    height: height,
  );
}

CanvasNode _referenceNode({
  required String id,
  required String refType,
  required String title,
  String refId = 'ref_id',
  double x = 50,
  double y = 60,
  double? width,
  double? height,
}) {
  return _canvasNode(
    id: id,
    type: canvasNodeTypeReference,
    title: title,
    content: '',
    x: x,
    y: y,
    width: width,
    height: height,
    refType: refType,
    refId: refId,
  );
}

CanvasNode _canvasNode({
  required String id,
  required String type,
  required String title,
  required String content,
  required double x,
  required double y,
  double? width,
  double? height,
  String? refType,
  String? refId,
}) {
  final now = DateTime(2026, 1, 1);
  return CanvasNode(
    id: id,
    canvasId: 'canvas_1',
    type: type,
    refType: refType,
    refId: refId,
    title: title,
    content: content,
    x: x,
    y: y,
    width: width,
    height: height,
    zIndex: 0,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

CanvasEdge _edge({
  required String id,
  required String type,
  String source = 'n1',
  String target = 'n2',
  String? label,
}) {
  return CanvasEdge(
    id: id,
    canvasId: 'canvas_1',
    sourceNodeId: source,
    targetNodeId: target,
    type: type,
    label: label,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

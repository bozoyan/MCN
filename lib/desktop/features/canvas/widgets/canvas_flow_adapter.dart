// 职责: 画布 Flow 适配 — 在 CanvasNode/CanvasEdge 领域模型与本地 flow 画布模型之间双向转换
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/canvas_layout.dart
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/third/flow/vyuh_node_flow.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/models/canvas_connection_path.dart';
import '../../../../shared/models/canvas_layout.dart';
import '../../../../shared/models/canvas_tree_layout.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../third/flow/vyuh_node_flow.dart' as flow;
import '../canvas_palette.dart';

/// 画布节点 anchor port 的 id 集合。
///
/// 设计稿(designs/desktop/canvas)采用边界落点：连线从源节点朝向目标那侧的
/// 边界射出，进入目标节点朝向源那侧的边界。vyuh_node_flow 的 Connection 基于
/// port 连线，因此预置 4 个 port(top/right/bottom/left)，按相对方向挑选。
///
/// 右侧 `anchor` 同时是可见的拖拽把手，外沿与节点右边界对齐。
const canvasAnchorRightPortId = 'anchor';
const canvasAnchorLeftPortId = 'anchor-left';
const canvasAnchorTopPortId = 'anchor-top';
const canvasAnchorBottomPortId = 'anchor-bottom';

/// 所有边界 port id，按 [top, right, bottom, left] 顺序。
const _canvasAnchorPortIds = [
  canvasAnchorTopPortId,
  canvasAnchorRightPortId,
  canvasAnchorBottomPortId,
  canvasAnchorLeftPortId,
];

/// port id 到 [flow.PortPosition] 的映射。
const _canvasAnchorPortPositions = {
  canvasAnchorTopPortId: flow.PortPosition.top,
  canvasAnchorRightPortId: flow.PortPosition.right,
  canvasAnchorBottomPortId: flow.PortPosition.bottom,
  canvasAnchorLeftPortId: flow.PortPosition.left,
};

/// 引用型节点默认尺寸。
///
/// 真源在 `lib/shared/models/canvas_layout.dart` —— AI 工具层按同一份尺寸算
/// 网格步长,两边分头写数字正是此前节点互相压 20px 的原因。
const Size canvasReferenceNodeSize = canvasReferenceDefaultSize;

typedef CanvasFlowController =
    flow.NodeFlowController<CanvasFlowNodeData, String>;
typedef CanvasFlowGraph = flow.NodeGraph<CanvasFlowNodeData, String>;
typedef CanvasFlowNode = flow.Node<CanvasFlowNodeData>;
typedef CanvasFlowConnection = flow.Connection<String>;

/// 便签节点。
///
/// 不用库自带的 `CommentNode`：它自绘内容(`buildWidget` 返回内部私有 widget)
/// 且构造不转发 `widgetBuilder`，board 的 `nodeBuilder` 拿不到它，无法实现
/// 设计稿要求的纸色 / serif 正文 / 署名。改为自定义节点 + [flow.ResizableMixin]
/// (库已导出)，渲染完全交给 `nodeBuilder`，vendored 库无需改动。
class CanvasStickyNode extends CanvasFlowNode
    with flow.ResizableMixin<CanvasFlowNodeData> {
  CanvasStickyNode({
    required super.id,
    required super.position,
    required super.size,
    required super.data,
    required super.ports,
  }) : super(type: canvasNodeTypeSticky);

  @override
  Size get minSize => canvasStickyMinSize;

  @override
  Size? get maxSize => canvasStickyMaxSize;

  /// [flow.ResizableMixin] 只在拖拽手柄时用 min/max 约束,程序化 setSize 不过约束
  /// (库内 CommentNode 同样自行覆写)。这里补上,避免 DB 里的异常尺寸直接生效。
  ///
  /// resize 走 `ResizableMixin.applyBounds → setSize`,因此顺带在这里同步 anchor
  /// port 的居中量 —— 否则拉大便签后连线仍挂在旧的中点上。
  @override
  void setSize(Size newSize) {
    super.setSize(
      Size(
        newSize.width.clamp(
          canvasStickyMinSize.width,
          canvasStickyMaxSize.width,
        ),
        newSize.height.clamp(
          canvasStickyMinSize.height,
          canvasStickyMaxSize.height,
        ),
      ),
    );
    syncCanvasAnchorPortOffsets(this);
  }
}

/// flow 节点附加数据：携带 DB 节点快照，便于事件回调回写 DB。
///
/// 引用型节点保存原始 `CanvasNode`(含 refType/refId/title)；
/// 便签节点同样保存原始 `CanvasNode`(标题/正文/纸色都从这里读)。
class CanvasFlowNodeData {
  const CanvasFlowNodeData({required this.node, this.isInvalid = false});

  /// 对应的 DB 节点快照(创建时复制)。
  final CanvasNode node;

  /// 引用型节点指向的资源是否已失效(渲染灰态)。
  /// 便签节点恒为 false。
  final bool isInvalid;
}

/// 见 [canvasAnchorPortOffsetFor]。
Offset canvasAnchorPortOffset(String portId, Size nodeSize) {
  final position = _canvasAnchorPortPositions[portId];
  return position == null
      ? Offset.zero
      : canvasAnchorPortOffsetFor(position, nodeSize);
}

/// 构建节点的 4 个边界 anchor port。
///
/// 按设计稿(designs/desktop/canvas)只有右侧把手常态可见并用于拖拽新建连线；
/// top/left/bottom 三个 port 常态隐形，拖拽连线经过时才高亮。
/// 所有 port 都设为 [flow.PortType.both]，这样任何方向都能做 source 或 target。
///
/// 不设置 `widgetBuilder`，保留 flow 原生 [flow.PortWidget] 提供的命中检测与
/// 连线拖拽手势；端口外观通过 [flow.Port.theme] 定制。
///
/// [nodeSize] 决定各 port 的居中量，见 [canvasAnchorPortOffset]。
List<flow.Port> buildCanvasAnchorPorts(RevericColors colors, Size nodeSize) {
  return _canvasAnchorPortIds.map((id) {
    final position = _canvasAnchorPortPositions[id]!;
    final isRight = id == canvasAnchorRightPortId;
    return flow.Port(
      id: id,
      name: '',
      type: flow.PortType.both,
      position: position,
      multiConnections: true,
      size: canvasAnchorPortSize,
      offset: canvasAnchorPortOffset(id, nodeSize),
      theme: flow.NodeFlowTheme.light.portTheme.copyWith(
        size: canvasAnchorPortSize,
        shape: flow.MarkerShapes.circle,
        color: isRight
            ? colors.surface.withValues(alpha: 0.35)
            : Colors.transparent,
        connectedColor: isRight
            ? colors.surface.withValues(alpha: 0.35)
            : Colors.transparent,
        highlightColor: colors.accent,
        borderColor: isRight
            ? colors.accent.withValues(alpha: 0.35)
            : Colors.transparent,
        highlightBorderColor: colors.accent,
        borderWidth: 1.5,
      ),
    );
  }).toList();
}

/// 节点尺寸变化后重算 anchor port 的居中量。
///
/// [flow.Port] 不可变，但 `Node.ports` 是 ObservableList 且提供 `updatePort`，
/// 因此换成新的 Port 实例即可，无需重建节点(重建会丢选中态与连线引用)。
void syncCanvasAnchorPortOffsets(CanvasFlowNode node) {
  final size = node.size.value;
  for (final port in node.ports.toList()) {
    final offset = canvasAnchorPortOffset(port.id, size);
    if (port.offset != offset) {
      node.updatePort(port.id, port.copyWith(offset: offset));
    }
  }
}

/// 将 DB 的 `CanvasNode` 转为 flow 节点。
///
/// 便签型与引用型都是普通 `flow.Node`(便签额外带 resize 能力),视觉统一由
/// board 的 `nodeBuilder` 负责,故此处只做几何与数据搬运。
CanvasFlowNode canvasNodeToFlowNode(
  CanvasNode node, {
  required RevericColors colors,
  bool isInvalid = false,
}) {
  final position = Offset(node.x, node.y);
  if (node.type == canvasNodeTypeSticky) {
    final size = Size(
      node.width ?? canvasStickyDefaultWidth,
      node.height ?? canvasStickyDefaultHeight,
    );
    return CanvasStickyNode(
      id: node.id,
      position: position,
      size: size,
      data: CanvasFlowNodeData(node: node, isInvalid: false),
      ports: buildCanvasAnchorPorts(colors, size),
    );
  }
  // reference
  final size = Size(
    node.width ?? canvasReferenceNodeSize.width,
    node.height ?? canvasReferenceNodeSize.height,
  );
  return CanvasFlowNode(
    id: node.id,
    type: node.type,
    position: position,
    size: size,
    data: CanvasFlowNodeData(node: node, isInvalid: isInvalid),
    ports: buildCanvasAnchorPorts(colors, size),
  );
}

/// 按 [canvasEdgeAnchorSides] 挑选进出 port。
(String sourcePortId, String targetPortId) canvasAnchorPortIdsForEdge(
  Offset sourceCenter,
  Offset targetCenter, {
  String? layout,
}) {
  final (source, target) = canvasEdgeAnchorSides(
    sourceCenter,
    targetCenter,
    layout: layout,
  );
  return (
    _canvasAnchorPortIdBySide[source]!,
    _canvasAnchorPortIdBySide[target]!,
  );
}

const _canvasAnchorPortIdBySide = {
  CanvasAnchorSide.top: canvasAnchorTopPortId,
  CanvasAnchorSide.right: canvasAnchorRightPortId,
  CanvasAnchorSide.bottom: canvasAnchorBottomPortId,
  CanvasAnchorSide.left: canvasAnchorLeftPortId,
};

/// 将 DB 的 `CanvasEdge` 转为 flow 连线。
///
/// 连线落点按设计稿采用「朝向目标那一侧的边界」。如果调用方提供了
/// [sourceCenter]/[targetCenter]，则结合 [layout] 为有向边选择进出端口；
/// 否则退化到默认的 right→left，便于单元测试只关心边属性时复用。
///
/// 边类型存在 connection.data 中；颜色/线型/箭头三者都按类型逐条设置
/// (而非走 theme)，因为同一张画布上 5 类边必须可分辨。
CanvasFlowConnection canvasEdgeToFlowConnection(
  CanvasEdge edge, {
  required RevericColors colors,
  Offset? sourceCenter,
  Offset? targetCenter,
  String? layout,
  List<Offset>? waypoints,
}) {
  final (
    sourcePortId,
    targetPortId,
  ) = (sourceCenter != null && targetCenter != null)
      ? canvasAnchorPortIdsForEdge(
          sourceCenter,
          targetCenter,
          layout: canvasEdgeDirected(edge.type) ? layout : null,
        )
      : (canvasAnchorRightPortId, canvasAnchorLeftPortId);
  final directed = canvasEdgeDirected(edge.type);
  return CanvasFlowConnection(
    id: edge.id,
    sourceNodeId: edge.sourceNodeId,
    sourcePortId: sourcePortId,
    targetNodeId: edge.targetNodeId,
    targetPortId: targetPortId,
    data: edge.type,
    style: canvasConnectionStyle(waypoints: waypoints, layout: layout),
    label: (edge.label == null || edge.label!.isEmpty)
        ? null
        : flow.ConnectionLabel.center(text: edge.label!),
    color: canvasEdgeColor(colors, edge.type),
    dashPattern: canvasEdgeDashPattern(edge.type),
    // 无向类型不画箭头(底层仍是有向存储)。
    startPoint: const flow.ConnectionEndPoint(
      shape: flow.MarkerShapes.none,
      size: Size.zero,
    ),
    endPoint: directed
        ? flow.ConnectionEndPoint(
            shape: flow.MarkerShapes.triangle,
            size: canvasConnectionArrowSize,
            color: canvasEdgeColor(colors, edge.type),
            borderColor: canvasEdgeColor(colors, edge.type),
          )
        : const flow.ConnectionEndPoint(
            shape: flow.MarkerShapes.none,
            size: Size.zero,
          ),
  );
}

/// 节点中心(画布坐标)。
///
/// 连线 port 方向按两端中心的相对位置挑选(见 [canvasAnchorPortIdsForEdge]),
/// 整图构建与增量挂载都用它算端点中心,口径必须一致。
Offset canvasNodeCenter(CanvasNode node) {
  return canvasNodeBounds(node).center;
}

/// 节点在画布中的矩形，供连线方向和保存后的视口定位共用尺寸口径。
Rect canvasNodeBounds(CanvasNode node) {
  final fallback = node.type == canvasNodeTypeSticky
      ? canvasStickyDefaultSize
      : canvasReferenceNodeSize;
  return Rect.fromLTWH(
    node.x,
    node.y,
    node.width ?? fallback.width,
    node.height ?? fallback.height,
  );
}

/// 见 [resolveCanvasTreeEdgeWaypoints]。
Map<(String, String), List<Offset>> canvasTreeEdgeWaypoints(
  List<CanvasNode> nodes,
  List<CanvasEdge> edges, {
  String? layout,
}) {
  return resolveCanvasTreeEdgeWaypoints(
    nodes: [
      for (final node in nodes)
        CanvasArrangeNode(
          id: node.id,
          sortOrder: node.sortOrder,
          size: canvasNodeBounds(node).size,
          position: Offset(node.x, node.y),
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
    layout: layout,
  );
}

/// 将整张画布(nodes + edges)转为 flow graph。
///
/// [invalidNodeIds] 用于标记引用失效的节点(渲染灰态)。
/// [colors] 用于派生边色/纸色/anchor 色,主题切换时由 board 重新 load。
/// [layout] 决定层级图的有向边进出方向，切换布局时应重建连线。
CanvasFlowGraph canvasContentToFlowGraph(
  List<CanvasNode> nodes,
  List<CanvasEdge> edges, {
  required RevericColors colors,
  String? layout,
  Set<String>? invalidNodeIds,
  flow.GraphViewport viewport = const flow.GraphViewport(),
}) {
  final invalid = invalidNodeIds ?? const <String>{};
  final flowNodes = [
    for (final node in nodes)
      canvasNodeToFlowNode(
        node,
        colors: colors,
        isInvalid: invalid.contains(node.id),
      ),
  ];
  final nodeById = {for (final node in nodes) node.id: node};
  final waypoints = canvasTreeEdgeWaypoints(nodes, edges, layout: layout);

  final flowEdges = [
    for (final edge in edges)
      if (nodeById.containsKey(edge.sourceNodeId) &&
          nodeById.containsKey(edge.targetNodeId))
        canvasEdgeToFlowConnection(
          edge,
          colors: colors,
          sourceCenter: canvasNodeCenter(nodeById[edge.sourceNodeId]!),
          targetCenter: canvasNodeCenter(nodeById[edge.targetNodeId]!),
          layout: layout,
          waypoints: canvasEdgeDirected(edge.type)
              ? waypoints[(edge.sourceNodeId, edge.targetNodeId)]
              : null,
        ),
  ];
  return CanvasFlowGraph(
    nodes: flowNodes,
    connections: flowEdges,
    viewport: viewport,
  );
}

/// 将 flow 节点位置回写为 DB `CanvasNode` 的拷贝(仅更新 x/y/width/height)。
///
/// 仅做反向几何转换；业务字段(refType/refId/title/content)由 service 层维护。
CanvasNode flowNodeToCanvasNode(
  CanvasFlowNode flowNode, {
  required CanvasNode previous,
}) {
  final position = flowNode.position.value;
  final size = flowNode.size.value;
  return previous.copyWith(
    x: position.dx,
    y: position.dy,
    width: Value(size.width),
    height: Value(size.height),
  );
}

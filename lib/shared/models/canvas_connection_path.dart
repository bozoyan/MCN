// 职责: 画布连线几何的唯一口径 —— anchor port 的尺寸与居中量、端点留白与箭头尺寸、
//       连线样式选择，以及不依赖 widget 树、直接走 vyuh_node_flow 同一条管线算出的路径段。
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/shared/services/canvas_export/svg.dart
//   lib/shared/components/waypoint_connection_style.dart

import 'package:flutter/widgets.dart' show Axis, Offset, Rect, Size;

import 'package:reveric/third/flow/vyuh_node_flow/lib/src/connections/styles/endpoint_position_calculator.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/connections/styles/path_segments.dart';

import '../../third/flow/vyuh_node_flow.dart' as flow;
import '../components/waypoint_connection_style.dart';
import 'canvas_layout.dart';

/// anchor port 的尺寸，决定连接点落在节点边界上的位置。
const Size canvasAnchorPortSize = Size(14, 14);

/// 连线两端与 port 之间的留白（设计稿 cvBoundary 的 pad=4）。
const double canvasConnectionGap = 4;

/// 有向边终点箭头的尺寸。
const Size canvasConnectionArrowSize = Size(9, 9);

/// 画布连线主题：flow 默认的曲率与端口延伸，外加两端留白。
final flow.ConnectionTheme canvasConnectionGeometryTheme = flow
    .ConnectionTheme
    .light
    .copyWith(
      style: flow.ConnectionStyles.bezier,
      startGap: canvasConnectionGap,
      endGap: canvasConnectionGap,
    );

const Map<CanvasAnchorSide, flow.PortPosition> canvasAnchorPortPositions = {
  CanvasAnchorSide.top: flow.PortPosition.top,
  CanvasAnchorSide.right: flow.PortPosition.right,
  CanvasAnchorSide.bottom: flow.PortPosition.bottom,
  CanvasAnchorSide.left: flow.PortPosition.left,
};

/// anchor port 在「垂直于所在边」方向上的居中量。
///
/// vyuh_node_flow 对**没有 NodeShape 的矩形节点**走
/// `PortPositionExtension.calculateOrigin(useAnchorForPerpendicularAxis: false)`
/// 分支：该轴的位置完全取自 `Port.offset`，而不是节点尺寸。默认 `Offset.zero`
/// 意味着 left/top port 的连接点落在节点左上角、right 落右上角、bottom 落左下角
/// —— 连线于是缩成节点角上的一个小钩(见 goldens/canvas_timeline_connections.png)。
/// 这里按节点尺寸把居中量补上，连接点与可见把手才回到各边中点。
Offset canvasAnchorPortOffsetFor(flow.PortPosition position, Size nodeSize) {
  return switch (position) {
    flow.PortPosition.left ||
    flow.PortPosition.right => Offset(0, nodeSize.height / 2),
    flow.PortPosition.top ||
    flow.PortPosition.bottom => Offset(nodeSize.width / 2, 0),
  };
}

/// 有跨层路点时走自留通道，否则用主题的 bezier（返回 null）。
flow.ConnectionStyle? canvasConnectionStyle({
  List<Offset>? waypoints,
  String? layout,
}) {
  if (waypoints == null || waypoints.isEmpty) {
    return null;
  }
  return WaypointConnectionStyle(
    waypoints: waypoints,
    portExtension: canvasConnectionGeometryTheme.portExtension,
    axis: layout == canvasLayoutTreeLr ? Axis.horizontal : Axis.vertical,
  );
}

/// 一条连线的路径段；有向边另给箭头中心与朝向（指向目标节点）。
typedef CanvasConnectionPath = ({
  Offset start,
  List<PathSegment> segments,
  ({Offset center, flow.PortPosition port})? arrow,
});

/// 按画布渲染同一条管线算连线：flow 节点的 port 连接点 → 端点留白与箭头让位
/// → 连线样式生成路径段。导出等没有 widget 树的场景用它得到与画布一致的线。
CanvasConnectionPath canvasConnectionPath({
  required Rect source,
  required Rect target,
  required bool directed,
  String? layout,
  List<Offset>? waypoints,
}) {
  final (sourceSide, targetSide) = canvasEdgeAnchorSides(
    source.center,
    target.center,
    layout: directed ? layout : null,
  );
  flow.Node<void> node(Rect rect, CanvasAnchorSide side) {
    final position = canvasAnchorPortPositions[side]!;
    return flow.Node<void>(
      id: '',
      type: '',
      position: rect.topLeft,
      data: null,
      size: rect.size,
      ports: [
        flow.Port(
          id: side.name,
          name: '',
          type: flow.PortType.both,
          position: position,
          size: canvasAnchorPortSize,
          offset: canvasAnchorPortOffsetFor(position, rect.size),
        ),
      ],
    );
  }

  final from = node(source, sourceSide), to = node(target, targetSide);
  final sourcePort = from.ports.single, targetPort = to.ports.single;
  final theme = canvasConnectionGeometryTheme;
  final start = EndpointPositionCalculator.calculatePortConnectionPoints(
    from.getConnectionPoint(sourcePort.id, portSize: canvasAnchorPortSize),
    sourcePort.position,
    Size.zero,
    gap: theme.startGap,
  );
  final end = EndpointPositionCalculator.calculatePortConnectionPoints(
    to.getConnectionPoint(targetPort.id, portSize: canvasAnchorPortSize),
    targetPort.position,
    directed ? canvasConnectionArrowSize : Size.zero,
    gap: theme.endGap,
  );
  final style =
      canvasConnectionStyle(
        waypoints: directed ? waypoints : null,
        layout: layout,
      ) ??
      theme.style;
  final result = style.createSegments(
    flow.ConnectionPathParameters(
      start: start.linePos,
      end: end.linePos,
      curvature: theme.bezierCurvature,
      sourcePort: sourcePort,
      targetPort: targetPort,
      cornerRadius: theme.cornerRadius,
      offset: theme.portExtension,
      backEdgeGap: theme.backEdgeGap,
      sourceNodeBounds: from.getBounds(),
      targetNodeBounds: to.getBounds(),
    ),
  );
  return (
    start: result.start,
    segments: result.segments,
    arrow: directed
        ? (center: end.endpointPos, port: targetPort.position)
        : null,
  );
}

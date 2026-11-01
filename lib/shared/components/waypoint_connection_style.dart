// 职责: 根据布局路点生成横向或纵向的分段贝塞尔连线，供图形编辑器共享。
// 关联文件:
//   lib/shared/models/canvas_connection_path.dart
//   lib/third/flow/vyuh_node_flow.dart

import 'package:flutter/material.dart';

import '../../third/flow/vyuh_node_flow.dart' as flow;
// PathSegment / CubicSegment 与 BezierConnectionStyle 没有走 connections.dart
// 这个 barrel 导出，因此直接导入对应的连线样式实现。
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/connections/styles/bezier_connection_style.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/connections/styles/waypoint_builder.dart';

/// 依次经过 [waypoints] 的连线走线。
///
/// 默认 bezier 只看两个端口。跨多层的边（分支跳到远处的合流点、空分支直连汇合点）
/// 会被拉成一条横穿画布的长弧，既压过中间的节点，也让「是 / 否」两条分支看起来
/// 完全不对称。这里把每个路点当成一个上下贯通的虚拟端口，逐段接起来。
///
/// [waypoints] 由调用方的布局算法给出，不在这里计算布局占位：
/// 布局把哪一列让出来，线就走哪一列。空分支只有一个路点时，它与对面分支节点的中心
/// 天然左右对称（两个槽位的偏移恒为 ±distance），于是两侧的外扩幅度一致。
///
/// 画布的层级排列也复用它：[axis] 为 [Axis.horizontal] 时路点自左向右排列，
/// 每段按右出左进接起来。
class WaypointConnectionStyle extends flow.ConnectionStyle {
  const WaypointConnectionStyle({
    required this.waypoints,
    required this.portExtension,
    this.axis = Axis.vertical,
  });

  /// 曲线要依次经过的点（画布坐标），沿 [axis] 方向排列。
  final List<Offset> waypoints;

  /// 连线的主走向。
  final Axis axis;

  /// 端口处的直线延伸长度，与主题的 portExtension 保持一致。
  final double portExtension;

  @override
  String get id => 'waypoints';

  @override
  String get displayName => 'Waypoints';

  @override
  ({Offset start, List<PathSegment> segments}) createSegments(
    flow.ConnectionPathParameters params,
  ) {
    final start = params.start;
    final end = params.end;
    final vertical = axis == Axis.vertical;
    double along(Offset point) => vertical ? point.dy : point.dx;
    // 只保留严格落在起点与终点之间的路点。画布还没排好版时（或用户拖动过节点）
    // 路点可能跑到端点外侧，那样接出来的形状会很怪，不如退回默认 bezier。
    final usable = [
      for (final waypoint in waypoints)
        if (along(waypoint) > along(start) && along(waypoint) < along(end))
          waypoint,
    ];
    if (usable.isEmpty) {
      return const BezierConnectionStyle().createSegments(params);
    }

    // 每一段都用默认 bezier 的同一个控制点公式（max(portExtension, 距离×curvature)），
    // 路点当成上下贯通的虚拟端口。第一段于是与对面分支那条边逐点镜像，
    // 「是 / 否」标签落在对称位置靠的就是这一点；自己另写一套公式会差出十几像素。
    final points = <Offset>[start, ...usable, end];
    return (
      start: start,
      segments: <PathSegment>[
        for (var i = 0; i < points.length - 1; i++)
          WaypointBuilder.createBezierSegment(
            start: points[i],
            end: points[i + 1],
            sourcePosition: vertical
                ? flow.PortPosition.bottom
                : flow.PortPosition.right,
            targetPosition: vertical
                ? flow.PortPosition.top
                : flow.PortPosition.left,
            curvature: params.curvature,
            portExtension: portExtension,
          ),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaypointConnectionStyle &&
          other.portExtension == portExtension &&
          other.axis == axis &&
          _sameWaypoints(other.waypoints, waypoints);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(waypoints), portExtension, axis);
}

bool _sameWaypoints(List<Offset> left, List<Offset> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

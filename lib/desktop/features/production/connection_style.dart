// 职责: 用直接连接端口的贝塞尔曲线绘制制作关系，允许曲线从节点背后经过。
// 关联文件:
//   lib/desktop/features/production/board.dart
//   lib/third/flow/vyuh_node_flow/lib/src/connections/styles/waypoint_builder.dart

import 'dart:ui';
import '../../../third/flow/vyuh_node_flow.dart' as flow;
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/connections/styles/waypoint_builder.dart';

/// 制作画布只表达输入与产物关系；反向连线也保持曲线，不切换成避障折线。
class ProductionConnectionStyle extends flow.ConnectionStyle {
  const ProductionConnectionStyle();

  @override
  String get id => 'production-bezier';

  @override
  String get displayName => 'Production Bezier';

  @override
  ({Offset start, List<PathSegment> segments}) createSegments(
    flow.ConnectionPathParameters params,
  ) => (
    start: params.start,
    segments: [
      WaypointBuilder.createBezierSegment(
        start: params.start,
        end: params.end,
        sourcePosition: params.effectiveSourcePosition,
        targetPosition: params.effectiveTargetPosition,
        curvature: params.curvature,
        portExtension: params.offset,
        sourceExtension: params.sourceOffset,
        targetExtension: params.targetOffset,
      ),
    ],
  );
}

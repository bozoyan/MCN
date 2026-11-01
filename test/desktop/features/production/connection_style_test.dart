// 职责: 验证制作画布的反向连线直接走曲线，拖线预览与落线遵循相同路径规则。
// 关联文件:
//   lib/desktop/features/production/connection_style.dart
//   lib/desktop/features/production/board.dart

import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/connection_style.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;

void main() {
  const style = ProductionConnectionStyle();
  final source = flow.Port(
    id: 'out',
    name: '',
    type: flow.PortType.output,
    position: flow.PortPosition.right,
  );
  final target = flow.Port(
    id: 'in',
    name: '',
    type: flow.PortType.input,
    position: flow.PortPosition.left,
  );

  for (final preview in [false, true]) {
    test(
      'backward connection stays between endpoint heights (preview=$preview)',
      () {
        // 尾帧在右上，下一段在左下；旧路由会绕到两张卡片的最上方。
        final params = flow.ConnectionPathParameters(
          start: const Offset(1386, 108),
          end: const Offset(755, 297),
          curvature: .5,
          sourcePort: source,
          targetPort: preview ? null : target,
          sourceNodeBounds: const Rect.fromLTWH(1126, 35, 260, 146),
          targetNodeBounds: preview
              ? null
              : const Rect.fromLTWH(755, 224, 260, 146),
        );
        final route = style.createSegments(params);
        final path = style.buildPath(route.start, route.segments);
        final metric = path.computeMetrics().single;
        expect(metric.getTangentForOffset(0)!.position, params.start);
        expect(
          (metric.getTangentForOffset(metric.length)!.position - params.end)
              .distance,
          lessThan(.01),
        );
        for (var i = 0; i <= 100; i++) {
          final point = metric
              .getTangentForOffset(metric.length * i / 100)!
              .position;
          expect(point.dy, inInclusiveRange(params.start.dy, params.end.dy));
        }
        // 从右口平滑离开，向右进入左口；不能退化成斜直线。
        expect(metric.getTangentForOffset(0)!.vector.dx, greaterThan(.99));
        expect(
          metric.getTangentForOffset(metric.length)!.vector.dx,
          greaterThan(.99),
        );
        expect(metric.length, lessThan(900));
        final hitRects = style.buildHitTestRects(
          route.start,
          route.segments,
          8,
        );
        final middle = metric.getTangentForOffset(metric.length / 2)!.position;
        expect(hitRects.any((rect) => rect.contains(middle)), isTrue);
      },
    );
  }
}

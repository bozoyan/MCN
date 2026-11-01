// 职责: 选中节点的出边流动高亮 — 把出边换成强调色流动虚线，取消选中后原样还原
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/canvas/widgets/canvas_edge_grow_effect.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
// 遵循的 Rules:
//   .agents/rules/performance.md

import 'dart:ui';

import '../../../../third/flow/vyuh_node_flow.dart' as flow;
import 'canvas_flow_adapter.dart';

/// 选中节点后，以它为源头的边沿「源 → 目标」方向流动。
///
/// 流动靠编辑器共享的 `repeat()` 节拍驱动：只要有边挂着 effect，整张画布就
/// 持续重绘，所以 effect 只跟选中态同生命周期 —— 取消选中必须摘干净。
///
/// 别的动效(新边生长、AI 导演)正占着的边不抢:它们演完摘掉 effect 后，
/// 调用方再 [sync] 一次即可补上高亮。
class CanvasEdgeFlowHighlight {
  CanvasEdgeFlowHighlight({required this.color});

  /// 高亮色(主题强调色),线和箭头同色。
  Color color;

  // 编辑器节拍周期 2s:speed 4 × (7 + 5) / 2s ≈ 24px/s,和缓但看得出方向。
  final flow.FlowingDashEffect _effect = flow.FlowingDashEffect(
    speed: 4,
    dashLength: 7,
    gapLength: 5,
  );

  /// 被高亮的连线 → 高亮前的颜色与箭头。
  ///
  /// 按对象而非 id 记:整图重载会用同 id 新建连线，旧对象的还原值不能
  /// 写到新对象上(边类型可能已经改了)。
  final Map<CanvasFlowConnection, (Color?, flow.ConnectionEndPoint?)> _restore =
      {};

  /// 按当前选中节点重算高亮集合。
  void sync(CanvasFlowController controller) {
    final selected = controller.selectedNodeIds.toSet();
    final targets = <CanvasFlowConnection>{
      if (selected.isNotEmpty)
        for (final connection in controller.connections)
          if (selected.contains(connection.sourceNodeId)) connection,
    };

    for (final connection in _restore.keys.toList()) {
      if (targets.contains(connection)) {
        continue;
      }
      final (restoreColor, restoreEndPoint) = _restore.remove(connection)!;
      if (!identical(controller.getConnection(connection.id), connection)) {
        continue;
      }
      if (connection.animationEffect == _effect) {
        connection.animationEffect = null;
      }
      connection.color = restoreColor;
      connection.endPoint = restoreEndPoint;
    }

    for (final connection in targets) {
      if (_restore.containsKey(connection) ||
          connection.animationEffect != null) {
        continue;
      }
      final endPoint = connection.endPoint;
      _restore[connection] = (connection.color, endPoint);
      connection.color = color;
      if (endPoint != null && endPoint.shape != flow.MarkerShapes.none) {
        connection.endPoint = endPoint.copyWith(
          color: color,
          borderColor: color,
        );
      }
      connection.animationEffect = _effect;
    }
  }
}

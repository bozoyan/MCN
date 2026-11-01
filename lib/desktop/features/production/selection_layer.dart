// 职责: 统一多选节点外框的绘制范围与整组拖动命中范围。
// 关联文件:
//   lib/desktop/features/production/board.dart
//   lib/desktop/features/production/node_card.dart
//   lib/shared/theme/canvas_colors.dart
//   lib/third/flow/vyuh_node_flow.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/performance.md
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/editor/unbounded_widgets.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/plugins/layer_provider.dart';

import '../../../shared/theme/canvas_colors.dart';
import '../../../shared/theme/theme.dart';
import '../../../third/flow/vyuh_node_flow.dart' as flow;
import 'node_card.dart';

class ProductionSelectionLayer extends flow.NodeFlowPlugin
    implements LayerProvider {
  ProductionSelectionLayer({this.groupBounds});

  /// 已选场次的外框，包含场次标题和留白。
  final Iterable<Rect> Function()? groupBounds;
  flow.NodeFlowController<String, String>? _controller;

  @override
  String get id => 'production-selection';

  @override
  LayerPosition get layerPosition => NodeFlowLayer.grid.after;

  @override
  void attach(flow.NodeFlowController controller) {
    _controller = controller as flow.NodeFlowController<String, String>;
  }

  @override
  void detach() => _controller = null;

  @override
  void onEvent(flow.GraphEvent event) {}

  /// 绘制和整组选区命中共用的画布坐标范围。
  Rect? get bounds {
    final controller = _controller;
    if (controller == null || controller.selectedNodeIds.length < 2) {
      return null;
    }
    final zoom = controller.viewportObservable.value.zoom;
    Rect? result;
    for (final id in controller.selectedNodeIds) {
      final node = controller.getNode(id);
      if (node == null) {
        continue;
      }
      final position = node.position.value;
      final size = node.size.value;
      final rect = Rect.fromLTRB(
        position.dx,
        position.dy - productionNodeHeaderExtent * productionHeaderScale(zoom),
        position.dx + size.width,
        position.dy + size.height,
      );
      result = result == null ? rect : result.expandToInclude(rect);
    }
    for (final rect in groupBounds?.call() ?? const <Rect>[]) {
      result = result == null ? rect : result.expandToInclude(rect);
    }
    return result?.inflate(RevericSpacing.x2l / zoom);
  }

  @override
  Widget? buildLayer(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final colors = RevericTheme.colorsOf(context);
    return UnboundedPositioned.fill(
      child: Observer(
        builder: (_) {
          if (controller.isDrawingSelection ||
              controller.selectedNodeIds.length < 2) {
            return const SizedBox.shrink();
          }
          final rect = bounds;
          if (rect == null) {
            return const SizedBox.shrink();
          }
          final zoom = controller.viewportObservable.value.zoom;
          return UnboundedStack(
            clipBehavior: Clip.none,
            children: [
              UnboundedPositioned(
                left: rect.left,
                top: rect.top,
                width: rect.width,
                height: rect.height,
                // 只在选区内拦住下层场次色带；节点、端口仍在上层命中。
                // 拖动生命周期由编辑器处理，与绘制共用 bounds。
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: CustomPaint(
                    key: const ValueKey('production-selection-bounds'),
                    painter: _SelectionPainter(
                      zoom: zoom,
                      border: colors.textMuted,
                      fill: canvasGlassHover(colors),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({
    required this.zoom,
    required this.border,
    required this.fill,
  });

  final double zoom;
  final Color border;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    // 抵消画布缩放，让描边、虚线和圆角保持屏幕尺寸，远景仍能看清。
    canvas.save();
    canvas.scale(1 / zoom);
    final rect = RRect.fromRectAndRadius(
      Offset.zero & (size * zoom),
      const Radius.circular(RevericRadius.xl),
    );
    canvas.drawRRect(rect, Paint()..color = fill);
    final path = Path()..addRRect(rect);
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      for (double at = 0; at < metric.length; at += RevericSpacing.sm) {
        dashed.addPath(
          metric.extractPath(at, at + RevericSpacing.xxs),
          Offset.zero,
        );
      }
    }
    canvas.drawPath(
      dashed,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SelectionPainter old) =>
      old.zoom != zoom || old.border != border || old.fill != fill;
}

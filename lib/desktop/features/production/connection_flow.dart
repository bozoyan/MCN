// 职责: 随制作画布的单选和多选更新关联连线的流动高亮及用途标签。
// 关联文件:
//   lib/desktop/features/production/board.dart
//   lib/shared/theme/canvas_colors.dart
//   lib/third/flow/vyuh_node_flow.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/performance.md
import 'package:mobx/mobx.dart';

import '../../../shared/theme/canvas_colors.dart';
import '../../../shared/theme/theme.dart';
import '../../../third/flow/vyuh_node_flow.dart' as flow;

class ProductionConnectionFlow extends flow.NodeFlowPlugin {
  ProductionConnectionFlow(RevericColors colors) : _colors = colors;

  RevericColors _colors;
  Map<String, String> _connectionLabels = const {};
  flow.ConnectionEffect? _effect;
  flow.NodeFlowController<String, String>? _controller;
  ReactionDisposer? _stop;

  @override
  String get id => 'production-connection-flow';

  @override
  void attach(flow.NodeFlowController controller) {
    final board = controller as flow.NodeFlowController<String, String>;
    _controller = board;
    // 选择与连线增删都来自控制器，框选不必经过父页面的单节点编辑焦点。
    _stop = reaction(
      (_) => (board.selectedNodeIds.toSet(), board.connections.toList()),
      (_) => _sync(),
      fireImmediately: true,
    );
  }

  void configure({
    required RevericColors colors,
    required Map<String, String> connectionLabels,
    required bool animate,
  }) {
    _colors = colors;
    _connectionLabels = connectionLabels;
    final soft = colors.accent.withValues(alpha: .3);
    _effect = animate
        ? flow.GradientFlowEffect(
            gradientLength: 48,
            connectionOpacity: .3,
            colors: [soft, colors.accent, soft],
          )
        : null;
    _sync();
  }

  void _sync() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final selected = controller.selectedNodeIds;
    final soft = canvasSoftEdgeColor(_colors);
    runInAction(() {
      for (final connection in controller.connections) {
        final on =
            selected.contains(connection.sourceNodeId) ||
            selected.contains(connection.targetNodeId);
        connection
          ..color = on
              ? _colors.accent.withValues(alpha: .95)
              : selected.isNotEmpty
              ? soft.withValues(alpha: soft.a * .45)
              : soft
          ..strokeWidth = on ? 2 : 1.6
          ..animationEffect = on ? _effect : null;
        // 单选时保留输入用途标签，多选不让所有标签同时挤在画布上。
        final label =
            selected.length == 1 && selected.contains(connection.targetNodeId)
            ? _connectionLabels[connection.id]
            : null;
        if (connection.label?.text != label) {
          connection.label = label == null
              ? null
              : flow.ConnectionLabel(text: label);
        }
      }
    });
  }

  @override
  void detach() {
    _stop?.call();
    _stop = null;
    for (final connection
        in _controller?.connections ?? const <flow.Connection<String>>[]) {
      if (identical(connection.animationEffect, _effect)) {
        connection.animationEffect = null;
      }
    }
    _controller = null;
  }

  @override
  void onEvent(flow.GraphEvent event) {}
}

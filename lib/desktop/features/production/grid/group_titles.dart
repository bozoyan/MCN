// 职责: 在分组外框上方提供可点击及拖动的标题命中层。
// 关联文件:
//   lib/desktop/features/production/board.dart
//   lib/desktop/features/production/grid/group_node.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/production.json
//   assets/translations/zh-CN/production.json
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/editor/element_scope.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/editor/drag_session.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/editor/unbounded_widgets.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/plugins/layer_provider.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../shared/models/production/group_layout.dart';
import '../../../../third/flow/vyuh_node_flow.dart' as flow;
import 'group_node.dart';

class ProductionGroupTitles extends flow.NodeFlowPlugin
    implements LayerProvider {
  Map<String, String> labels = const {};
  flow.NodeFlowController<String, String>? _controller;
  @override
  String get id => 'production-group-titles';
  @override
  LayerPosition get layerPosition => NodeFlowLayer.middleNodes.before;
  @override
  void attach(flow.NodeFlowController controller) =>
      _controller = controller as flow.NodeFlowController<String, String>;
  @override
  void detach() => _controller = null;
  @override
  void onEvent(flow.GraphEvent event) {}
  @override
  Widget? buildLayer(BuildContext context) {
    final controller = _controller!;
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    return UnboundedPositioned.fill(
      child: Observer(
        builder: (_) => UnboundedStack(
          clipBehavior: Clip.none,
          children: [
            for (final group
                in controller.nodes.values.whereType<ProductionFlowGroup>())
              UnboundedPositioned(
                left: group.visualPosition.value.dx,
                top: group.visualPosition.value.dy - productionCardHeaderExtent,
                width: group.size.value.width,
                height: productionCardHeaderExtent,
                child: ElementScope(
                  createSession: () =>
                      controller.createSession(DragSessionType.nodeDrag),
                  onDragStart: (_) => controller.startNodeDrag(group.id),
                  onDragUpdate: (details) =>
                      controller.moveNodeDrag(details.delta),
                  onDragEnd: (_) => controller.endNodeDrag(),
                  onTap: () {
                    controller.selectNode(group.id);
                    controller.events.node?.onTap?.call(group);
                  },
                  cursor: SystemMouseCursors.grab,
                  child: Text(
                    labels[group.id] ?? '',
                    key: ValueKey('group-title/${group.id}'),
                    style: typo.uiSmallSemibold.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

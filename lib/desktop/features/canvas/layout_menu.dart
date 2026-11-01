// 职责: 使用 Reveric 菜单展示画布排列操作，按图结构和忙碌状态禁用无效操作。
// 关联文件:
//   lib/shared/components/reveric_context_menu.dart
//   lib/desktop/features/canvas/edit_session.dart
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/shared/providers/canvas_providers.dart
//   lib/shared/models/canvas_layout.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/components/reveric_context_menu.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/canvas_layout.dart';
import '../../../shared/providers/canvas_providers.dart';
import '../../../shared/theme/theme.dart';
import 'edit_session.dart';
import 'widgets/floating_cluster.dart';

class CanvasLayoutMenu extends ConsumerWidget {
  const CanvasLayoutMenu({
    super.key,
    required this.canvasId,
    required this.databasePath,
    required this.session,
    required this.onSelected,
  });
  final String canvasId;
  final String databasePath;
  final CanvasEditSession session;
  final Future<void> Function(String mode) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (canvasId: canvasId, databasePath: databasePath);
    final content = ref.watch(canvasContentStreamProvider(key)).value;
    final ids =
        content?.nodes.map((node) => node.id).toSet() ?? const <String>{};
    final edges = content?.edges ?? const [];
    final directed = edges.any(
      (edge) =>
          isCanvasEdgeDirected(edge.type) &&
          ids.contains(edge.sourceNodeId) &&
          ids.contains(edge.targetNodeId),
    );
    final labels = {
      canvasLayoutTidy: context.t(LocaleKeys.canvasLayoutTidy),
      canvasLayoutAuto: context.t(LocaleKeys.canvasLayoutAuto),
      canvasLayoutTreeLr: context.t(LocaleKeys.canvasLayoutTreeLr),
      canvasLayoutTreeTb: context.t(LocaleKeys.canvasLayoutTreeTb),
      canvasLayoutGrid: context.t(LocaleKeys.canvasLayoutGrid),
    };
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return CanvasFloatingButton(
          icon: RevericIcons.account_tree,
          tooltip: ids.length < 2
              ? context.t(LocaleKeys.canvasLayoutNeedsNodes)
              : context.t(LocaleKeys.canvasArrange),
          onTap: ids.length < 2 || session.busy
              ? null
              : () {
                  final box = context.findRenderObject() as RenderBox;
                  // 按钮在画布左下角的工具簇里，菜单向上展开。
                  unawaited(
                    showRevericContextMenu(
                      context: context,
                      anchor: Alignment.bottomLeft,
                      position: box.localToGlobal(
                        const Offset(0, -RevericSpacing.xs),
                      ),
                      entries: [
                        for (final mode in canvasLayoutModes)
                          RevericMenuItem(
                            label: labels[mode]!,
                            enabled:
                                !((mode == canvasLayoutTreeLr ||
                                        mode == canvasLayoutTreeTb) &&
                                    !directed),
                            tooltip: context.t(
                              (mode == canvasLayoutTreeLr ||
                                          mode == canvasLayoutTreeTb) &&
                                      !directed
                                  ? LocaleKeys.canvasLayoutNeedsDirectedEdges
                                  : mode == canvasLayoutTidy
                                  ? LocaleKeys.canvasLayoutTidyTooltip
                                  : mode == canvasLayoutAuto
                                  ? LocaleKeys.canvasAutoLayoutTooltip
                                  : LocaleKeys.canvasLayoutMovesAll,
                            ),
                            onTap: () => unawaited(onSelected(mode)),
                          ),
                      ],
                    ),
                  );
                },
        );
      },
    );
  }
}

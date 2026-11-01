// 职责: 画布可视区域 —— 顶栏 + 画布板 + 画布自身的编辑动作，不含聊天面板与窗口 chrome
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/canvas/widgets/canvas_toolbar.dart
//   lib/desktop/features/canvas/widgets/canvas_resource_picker.dart
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/desktop/features/canvas/edit_session.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/widget-decomposition.md

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/logger/app_logger.dart';
import '../../../../shared/models/canvas_layout.dart';
import '../../../../shared/models/novel_workspace.dart';
import '../../../../shared/providers/canvas_providers.dart';
import '../../../../shared/providers/screenplay_workspace_state_provider.dart';
import '../../../../shared/providers/workspace_navigation_provider.dart';
import '../../../../shared/services/canvas_service.dart';
import '../../../../third/flow/vyuh_node_flow.dart' as flow;
import '../edit_session.dart';
import '../export_button.dart';
import 'canvas_ai_focus_layer.dart';
import 'canvas_board.dart';
import 'canvas_detail_layer.dart';
import 'canvas_flow_adapter.dart';
import 'canvas_resource_picker.dart';
import 'canvas_toolbar.dart';

final _log = AppLogger.forModule('CanvasRegion');

/// 画布 LOD：缩到最小也必须能看见节点卡片。
///
/// 库的 [flow.DetailVisibility.minimal] 会关掉节点内容，只留 nodeTheme 画的矩形——
/// 而画布把 nodeTheme 设成了全透明(卡片视觉由 nodeBuilder 自绘)，于是
/// zoom < 0.28 时整片节点直接消失。这里只放开 showNodeContent，其余降级(隐藏
/// port / 标签 / resize 手柄)保留，性能收益不变。
flow.LodPlugin _canvasLodPlugin() {
  return flow.LodPlugin(
    minVisibility: flow.DetailVisibility.minimal.copyWith(
      showNodeContent: true,
    ),
  );
}

/// 一张画布的可见区域：顶栏 + 画布板 + 画布自身的编辑动作。
///
/// 只负责画布本身 —— 聊天面板、折叠 rail、窗口 chrome 都归宿主。工作区把它嵌进
/// 主内容区，复用工作区的聊天面板。
class CanvasRegion extends HookConsumerWidget {
  const CanvasRegion({
    super.key,
    required this.canvasId,
    required this.databasePath,
    this.workId,
    this.exportSource,
    this.novelName,
    this.showToolbar = false,
    this.onClose,
    this.toolbarLeadingKey,
  }) : assert(!showToolbar || onClose != null);

  final String canvasId;
  final String databasePath;
  final String? workId;
  final ({String id, String contentKind})? exportSource;
  final String? novelName;

  /// 是否显示画布自己的页面级顶栏。
  ///
  /// 普通画布嵌在工作区时由工作区主面板统一提供面包屑和保存入口；
  /// 独立承载区域时可选择显示这里的顶栏。
  final bool showToolbar;

  /// 独立页顶栏关闭按钮；[showToolbar] 为 true 时必须提供。
  final VoidCallback? onClose;

  /// 标题栏拖拽排除区域 key（Windows 系统按钮覆盖在标题栏 overlay 上时需要）。
  final GlobalKey? toolbarLeadingKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // flow controller（区域级单例），工具栏/画布板共享。
    // detailLayer 在 board 的同级前景层渲染，不能注册为 flow 内部 plugin：
    // 否则编辑器根 Listener 会把其输入点击当作空画布点击而清选中态。
    final editSession = useMemoized(CanvasEditSession.new, [
      canvasId,
      databasePath,
    ]);
    useListenable(editSession);
    useEffect(() => editSession.dispose, [editSession]);
    final canvasService = ref.watch(canvasServiceProvider(databasePath));
    useEffect(() {
      Future<CanvasLayoutSaveResult> boundary(
        Future<CanvasLayoutSaveResult> Function() action,
      ) {
        return editSession.runLayout(() async {
          if (!context.mounted) {
            throw const CanvasEditSessionException('disposed');
          }
          FocusManager.instance.primaryFocus?.unfocus();
          return action();
        });
      }

      canvasService.registerLayoutBoundary(canvasId, boundary);
      return () => canvasService.unregisterLayoutBoundary(canvasId, boundary);
    }, [canvasService, canvasId, editSession]);
    final detailLayer = useMemoized(CanvasDetailLayer.new, const []);
    final focusLayer = useMemoized(CanvasAiFocusLayer.new, const []);
    final controller = useMemoized(
      () => CanvasFlowController(
        config: flow.NodeFlowConfig(
          minZoom: 0.2,
          maxZoom: 3.0,
          showAttribution: false,
          plugins: [
            ...flow.NodeFlowConfig.defaultPlugins().where(
              (plugin) => plugin is! flow.LodPlugin,
            ),
            _canvasLodPlugin(),
            focusLayer,
            editSession,
          ],
        ),
      ),
      [detailLayer, focusLayer, editSession],
    );

    useEffect(() {
      return controller.dispose;
    }, [controller]);

    final canvasName = showToolbar
        ? ref
                  .watch(
                    canvasEntryProvider((
                      canvasId: canvasId,
                      databasePath: databasePath,
                    )),
                  )
                  .asData
                  ?.value
                  ?.name ??
              ''
        : '';

    // 失效引用节点：供顶栏计数 + 画布板灰态。
    final invalidIds =
        ref
            .watch(
              canvasInvalidNodeIdsProvider((
                canvasId: canvasId,
                databasePath: databasePath,
              )),
            )
            .asData
            ?.value ??
        const <String>{};

    /// 保存画布：节点/边/便签内容已实时写入 DB，这里刷新引用标题缓存并提示用户。
    Future<void> handleSave() async {
      try {
        await editSession.flushAndWait();
        if (!context.mounted) {
          return;
        }
        await ref
            .read(canvasServiceProvider(databasePath))
            .refreshReferenceTitlesForCanvas(canvasId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonSaved))),
          );
        }
      } catch (error, stackTrace) {
        _log.error(
          'Canvas save failed id=$canvasId',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
          );
        }
      }
    }

    // 便签：在视口中心新建一张空白便签(带默认纸色)。
    Future<void> handleAddSticky() async {
      final center = controller.getViewportCenter();
      try {
        final service = ref.read(canvasServiceProvider(databasePath));
        await editSession.write(
          'add-sticky',
          () => service.addNode(
            canvasId: canvasId,
            type: canvasNodeTypeSticky,
            content: '',
            x: center.dx,
            y: center.dy,
            style: const {canvasNodeColorStyleKey: canvasStickyColorDefault},
          ),
        );
      } catch (error, stackTrace) {
        _log.error(
          'action=add_sticky phase=write_failure canvasId=$canvasId '
          'x=${center.dx} y=${center.dy}',
          error: error,
          stackTrace: stackTrace,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    Future<void> handleLayout(String mode) async {
      try {
        if (editSession.isComposing) {
          throw const CanvasEditSessionException('input_composing');
        }
        final result = await canvasService.applyLayout(canvasId, mode);
        if (!context.mounted) {
          return;
        }
        // 保存完成不代表 board 的订阅已送达新坐标。按提交后的内容定位，
        // 不从可能仍持有旧图的 controller 计算范围；后续重载会保留这个视口。
        final content = await canvasService.watchCanvasContent(canvasId).first;
        if (!context.mounted || controller.canvasKey.currentContext == null) {
          return;
        }
        if (content.nodes.isNotEmpty) {
          final bounds = content.nodes
              .map(canvasNodeBounds)
              .reduce((a, b) => a.expandToInclude(b));
          controller.animateToBounds(
            flow.GraphRect(bounds),
            duration: Duration.zero,
          );
        }
        final message = result.moved > 0
            ? context.t(
                LocaleKeys.canvasLayoutMoved,
                namedArgs: {'count': '${result.moved}'},
              )
            : context.t(
                result.modeChanged
                    ? LocaleKeys.canvasLayoutSaved
                    : LocaleKeys.canvasLayoutUnchanged,
              );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      } catch (error, stackTrace) {
        _log.error(
          'Canvas layout failed id=$canvasId mode=$mode',
          error: error,
          stackTrace: stackTrace,
        );
        if (!context.mounted) {
          return;
        }
        final message = switch (error) {
          CanvasEditSessionException(code: 'input_composing') =>
            LocaleKeys.canvasFinishInput,
          CanvasServiceException(errorCode: 'layout_conflict') =>
            LocaleKeys.canvasLayoutConflict,
          CanvasServiceException(errorCode: 'layout_requires_directed_edges') =>
            LocaleKeys.canvasLayoutNeedsDirectedEdges,
          _ => LocaleKeys.commonSaveFailed,
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.t(message))));
      }
    }

    // 清理失效：循环软删所有失效引用节点(stream 自动刷新)。
    Future<void> handleCleanDead() async {
      final service = ref.read(canvasServiceProvider(databasePath));
      for (final id in invalidIds) {
        await editSession.write('delete:$id', () => service.softDeleteNode(id));
      }
    }

    // 引用：打开资源选择器浮层。
    Future<void> handleAddReference() async {
      final center = controller.getViewportCenter();
      await showCanvasResourcePicker(
        context: context,
        databasePath: databasePath,
        canvasId: canvasId,
        viewportCenter: center.offset,
        editSession: editSession,
      );
    }

    Future<void> handleOpenScene(String sceneId) async {
      final navigation = ref.read(workspaceNavigationProvider.notifier);
      try {
        await ref
            .read(
              screenplayWorkspaceStateControllerProvider(
                workId!,
                databasePath,
              ).notifier,
            )
            .openSceneScript(sceneId);
        if (!context.mounted) {
          return;
        }
        navigation.request(
          WorkspaceNavigationRequest(
            section: NovelWorkspaceSection.screenplay_script,
            itemId: sceneId,
          ),
        );
      } catch (error, stackTrace) {
        _log.error(
          'Opening canvas scene failed id=$sceneId',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.t(LocaleKeys.canvasOpenSceneFailed)),
            ),
          );
        }
      }
    }

    return Column(
      children: [
        if (showToolbar)
          CanvasToolbar(
            leadingKey: toolbarLeadingKey,
            onClose: onClose!,
            onSave: () => unawaited(handleSave()),
            canvasName: canvasName,
            novelName: novelName,
            locked: false,
          ),
        Expanded(
          child: CanvasBoard(
            canvasId: canvasId,
            databasePath: databasePath,
            controller: controller,
            onOpenScene: workId == null ? null : handleOpenScene,
            exportControl: exportSource == null
                ? null
                : CanvasExportButton(
                    source: (
                      canvasId: canvasId,
                      databasePath: databasePath,
                      workId: exportSource!.id,
                      contentKind: exportSource!.contentKind,
                    ),
                    session: editSession,
                    onBlocked: null,
                  ),
            detailLayer: detailLayer,
            focusLayer: focusLayer,
            invalidNodeIds: invalidIds,
            onAddReference: handleAddReference,
            onAddSticky: handleAddSticky,
            onLayout: handleLayout,
            editSession: editSession,
            onCleanDead: handleCleanDead,
            editable: !editSession.editingLocked,
          ),
        ),
      ],
    );
  }
}

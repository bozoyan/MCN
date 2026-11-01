// 职责: 画布原地编辑浮层 — 选中节点的详情面板、选中连线的中点编辑器、连线落点的类型选择卡
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_edge_type_picker.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
//   lib/desktop/features/canvas/widgets/canvas_sticky_editor.dart
//   lib/desktop/features/canvas/edit_session.dart
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/performance.md
//   .agents/rules/text-input-ime.md

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../../../../shared/components/reveric_context_menu.dart';
import '../../../../shared/components/reveric_more_menu_button.dart';
import '../../../../shared/components/reveric_text_field.dart';
import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../third/flow/vyuh_node_flow.dart' as flow;
import '../canvas_palette.dart';
import '../scene_reference.dart';
import '../edit_session.dart';
import '../../../../shared/utils/text_input_composing.dart';
import 'canvas_edge_type_picker.dart';
import 'canvas_flow_adapter.dart';
import 'canvas_node_color_picker.dart';
import 'canvas_node_widget.dart';
import 'canvas_sticky_editor.dart';

/// 连线落点待选类型的请求。
///
/// 从 anchor 拖出连线松手后先记下两端与落点屏幕位置，等作者选定类型才落库。
class CanvasPendingEdge {
  const CanvasPendingEdge({
    required this.sourceNodeId,
    required this.targetNodeId,
    required this.at,
  });

  final String sourceNodeId;
  final String targetNodeId;

  /// 落点的屏幕坐标(相对画布)。
  final Offset at;
}

/// 详情浮层的回调集合。由 board 注入，plugin 只负责定位与渲染。
class CanvasDetailCallbacks {
  const CanvasDetailCallbacks({
    required this.onSelectNode,
    required this.onDeleteNode,
    required this.onStickyTitleChanged,
    required this.onStickyContentChanged,
    required this.onNodeColorChanged,
    required this.onEdgeTypeChanged,
    required this.onEdgeLabelChanged,
    required this.onDeleteEdge,
    required this.onClearSelection,
    required this.onPickPendingEdgeType,
    required this.onCancelPendingEdge,
    this.onOpenScene,
    this.editSession,
  });

  final ValueChanged<String> onSelectNode;
  final ValueChanged<String> onDeleteNode;
  final Future<void> Function(String nodeId, String title) onStickyTitleChanged;
  final Future<void> Function(String nodeId, String content)
  onStickyContentChanged;
  final void Function(CanvasNode node, String? color) onNodeColorChanged;
  final void Function(String edgeId, String type) onEdgeTypeChanged;
  final Future<void> Function(String edgeId, String label) onEdgeLabelChanged;
  final ValueChanged<String> onDeleteEdge;
  final VoidCallback onClearSelection;
  final ValueChanged<String> onPickPendingEdgeType;
  final VoidCallback onCancelPendingEdge;
  final ValueChanged<String>? onOpenScene;
  final CanvasEditSession? editSession;
}

/// 画布原地编辑浮层的状态与构建入口。
///
/// 不能作为 `NodeFlowEditor` 内部 overlay：编辑器根 [Listener] 会把浮层中的点击
/// 重新命中为空白画布并清掉选中态，面板会在 TextField 获得焦点前消失。由 board
/// 放在编辑器的同级前景层后，浮层才能先命中并保留选中态。
class CanvasDetailLayer {
  CanvasDetailLayer();

  /// 由 board 每次 rebuild 时同步(回调闭包会捕获最新的 ref/context)。
  CanvasDetailCallbacks? callbacks;

  /// 当前画布内容快照，用于查连线列表与边数据。
  ({List<CanvasNode> nodes, List<CanvasEdge> edges}) content = (
    nodes: const [],
    edges: const [],
  );

  /// 待选类型的连线；非空时渲染类型选择卡。
  CanvasPendingEdge? pendingEdge;

  /// 在画布根 Stack 中构建；不能放入 [flow.NodeFlowEditor] 的内部 Stack。
  Widget buildOverlay(
    CanvasFlowController controller, {
    String? databasePath,
    bool ignoreInput = false,
  }) {
    final callbacks = this.callbacks;
    if (callbacks == null) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: ignoreInput,
        child: _CanvasDetailOverlay(
          controller: controller,
          callbacks: callbacks,
          content: content,
          pendingEdge: pendingEdge,
          databasePath: databasePath,
        ),
      ),
    );
  }
}

class _CanvasDetailOverlay extends StatelessWidget {
  const _CanvasDetailOverlay({
    required this.controller,
    required this.callbacks,
    required this.content,
    required this.pendingEdge,
    this.databasePath,
  });

  final CanvasFlowController controller;
  final CanvasDetailCallbacks callbacks;
  final ({List<CanvasNode> nodes, List<CanvasEdge> edges}) content;
  final CanvasPendingEdge? pendingEdge;
  final String? databasePath;

  /// 连线编辑器宽度。
  static const double _edgeEditorWidth = 248;

  /// 面板与节点/连线之间的间距。
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final viewport = controller.viewportObservable.value;
        final children = <Widget>[];

        // ---- 选中节点的详情面板 ----
        final selectedNodeId = controller.selectedNodeIdsObservable.isEmpty
            ? null
            : controller.selectedNodeIdsObservable.last;
        if (selectedNodeId != null) {
          final flowNode = controller.getNode(selectedNodeId);
          final dbNode = content.nodes
              .where((n) => n.id == selectedNodeId)
              .firstOrNull;
          if (flowNode != null && dbNode != null) {
            // 触发 MobX 依赖：节点拖动/缩放时面板跟随。
            final position = flowNode.position.value;
            final size = flowNode.size.value;
            final anchor = viewport
                .toScreen(
                  flow.GraphPosition(
                    position + Offset(0, size.height + _gap / viewport.zoom),
                  ),
                )
                .offset;
            children.add(
              Positioned(
                left: anchor.dx,
                top: anchor.dy,
                child: _NodeDetailPanel(
                  node: dbNode,
                  isInvalid: flowNode.data.isInvalid,
                  content: content,
                  callbacks: callbacks,
                  databasePath: databasePath,
                ),
              ),
            );
          }
        }

        // ---- 选中连线的中点编辑器 ----
        final selectedEdgeId =
            controller.selectedConnectionIdsObservable.isEmpty
            ? null
            : controller.selectedConnectionIdsObservable.last;
        if (selectedEdgeId != null) {
          final edge = content.edges
              .where((e) => e.id == selectedEdgeId)
              .firstOrNull;
          final midpoint = _connectionMidpoint(controller, selectedEdgeId);
          if (edge != null && midpoint != null) {
            final screen = viewport
                .toScreen(flow.GraphPosition(midpoint))
                .offset;
            children.add(
              Positioned(
                left: screen.dx - _edgeEditorWidth / 2,
                top: screen.dy + _gap,
                child: _EdgeEditorPanel(
                  width: _edgeEditorWidth,
                  edge: edge,
                  callbacks: callbacks,
                ),
              ),
            );
          }
        }

        // ---- 连线落点的类型选择卡 ----
        final pending = pendingEdge;
        if (pending != null) {
          children.add(
            Positioned(
              left: pending.at.dx - CanvasEdgeTypePickerCard.width / 2,
              top: pending.at.dy + _gap,
              child: CanvasEdgeTypePickerCard(
                onPick: callbacks.onPickPendingEdgeType,
                onCancel: callbacks.onCancelPendingEdge,
              ),
            ),
          );
        }

        if (children.isEmpty) {
          return const SizedBox.shrink();
        }
        return Stack(clipBehavior: Clip.none, children: children);
      },
    );
  }
}

/// 取连线路径中点(graph 坐标)。
///
/// 优先读 flow 的 path cache，与实际渲染的曲线对齐(而非两端连线的几何中点)，
/// 编辑器才会正好落在作者看到的那条线上。
Offset? _connectionMidpoint(CanvasFlowController controller, String edgeId) {
  if (!controller.isConnectionPainterInitialized) {
    return null;
  }
  final path = controller.getConnectionPath(edgeId);
  if (path == null) {
    return null;
  }
  final metrics = path.computeMetrics().toList(growable: false);
  if (metrics.isEmpty || metrics.first.length <= 0) {
    return null;
  }
  return metrics.first.getTangentForOffset(metrics.first.length / 2)?.position;
}

/// 选中节点的原地详情面板。
class _NodeDetailPanel extends StatelessWidget {
  const _NodeDetailPanel({
    required this.node,
    required this.isInvalid,
    required this.content,
    required this.callbacks,
    this.databasePath,
  });

  final CanvasNode node;
  final bool isInvalid;
  final ({List<CanvasNode> nodes, List<CanvasEdge> edges}) content;
  final CanvasDetailCallbacks callbacks;
  final String? databasePath;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final linked = content.edges
        .where((e) => e.sourceNodeId == node.id || e.targetNodeId == node.id)
        .toList(growable: false);
    final isSticky = node.type == canvasNodeTypeSticky;

    return CanvasFloatingCard(
      width: 272,
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x2l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSticky)
              CanvasStickyEditor(
                node: node,
                session: callbacks.editSession,
                actions: CanvasStickyActions(
                  onTitleChanged: (value) =>
                      callbacks.onStickyTitleChanged(node.id, value),
                  onContentChanged: (value) =>
                      callbacks.onStickyContentChanged(node.id, value),
                  onColorChanged: (value) =>
                      callbacks.onNodeColorChanged(node, value),
                  onDelete: () => callbacks.onDeleteNode(node.id),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isInvalid
                          ? context.t(LocaleKeys.canvasInvalidReferenceDetail)
                          : canvasRefTypeLabel(
                              context,
                              node.refType ?? canvasNodeRefTypeDocument,
                            ),
                      style: typo.uiTiny.copyWith(
                        color: colors.textMuted,
                        height: 1.6,
                      ),
                    ),
                  ),
                  RevericMoreMenuButton(
                    iconSize: 16,
                    entries: () => [
                      RevericMenuItem(
                        icon: RevericIcons.delete_outline,
                        iconColor: colors.warningText,
                        labelColor: colors.warningText,
                        label: isInvalid
                            ? context.t(LocaleKeys.canvasRemoveInvalidNode)
                            : context.t(LocaleKeys.commonDelete),
                        onTap: () => callbacks.onDeleteNode(node.id),
                      ),
                    ],
                  ),
                ],
              ),
              if (node.refType == canvasNodeRefTypeScreenplayScene &&
                  node.refId != null &&
                  databasePath != null)
                CanvasSceneReferenceDetails(
                  databasePath: databasePath!,
                  sceneId: node.refId!,
                  onOpen: callbacks.onOpenScene,
                ),
              if (!isInvalid) ...[
                const SizedBox(height: RevericSpacing.md),
                CanvasNodeColorPicker(
                  value: canvasNodeColorValueOf(node.style),
                  allowNone: true,
                  onChanged: (value) =>
                      callbacks.onNodeColorChanged(node, value),
                ),
              ],
              const SizedBox(height: RevericSpacing.lg),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: RevericSpacing.lg),
              _SectionLabel(
                '${context.t(LocaleKeys.canvasNodeConnections)} ${linked.length}',
              ),
              if (linked.isEmpty)
                Text(
                  context.t(LocaleKeys.canvasNodeConnectionsEmpty),
                  style: typo.uiTiny.copyWith(
                    color: colors.textMuted,
                    height: 1.6,
                  ),
                )
              else
                for (final edge in linked)
                  _LinkedEdgeRow(
                    edge: edge,
                    selfNodeId: node.id,
                    nodes: content.nodes,
                    onTap: callbacks.onSelectNode,
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
      child: Text(
        text,
        style: typo.uiTinySemibold.copyWith(
          color: colors.textSubtle,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// 详情面板里的一条连线：方向箭头 + 对端标题 + 类型·说明。点击跳到对端节��。
class _LinkedEdgeRow extends StatelessWidget {
  const _LinkedEdgeRow({
    required this.edge,
    required this.selfNodeId,
    required this.nodes,
    required this.onTap,
  });

  final CanvasEdge edge;
  final String selfNodeId;
  final List<CanvasNode> nodes;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isOutgoing = edge.sourceNodeId == selfNodeId;
    final otherId = isOutgoing ? edge.targetNodeId : edge.sourceNodeId;
    final other = nodes.where((n) => n.id == otherId).firstOrNull;
    final label = edge.label;

    return InkWell(
      onTap: () => onTap(otherId),
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      hoverColor: colors.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.xs,
          vertical: 5,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: RevericIcon(
                isOutgoing
                    ? RevericIcons.arrow_forward
                    : RevericIcons.arrow_back,
                size: 13,
                color: canvasEdgeColor(colors, edge.type),
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    other == null || other.title.isEmpty ? '—' : other.title,
                    style: typo.uiSmall.copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    label == null || label.isEmpty
                        ? canvasEdgeTypeLabel(context, edge.type)
                        : '${canvasEdgeTypeLabel(context, edge.type)} · $label',
                    style: typo.uiTiny.copyWith(color: colors.textSubtle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选中连线的中点原地编辑器：改类型 / 改说明 / 删除。
class _EdgeEditorPanel extends StatefulWidget {
  const _EdgeEditorPanel({
    required this.width,
    required this.edge,
    required this.callbacks,
  });

  final double width;
  final CanvasEdge edge;
  final CanvasDetailCallbacks callbacks;

  @override
  State<_EdgeEditorPanel> createState() => _EdgeEditorPanelState();
}

class _EdgeEditorPanelState extends State<_EdgeEditorPanel> {
  late final TextEditingController _labelController;
  late String _savedLabel;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.edge.label ?? '');
    _savedLabel = _labelController.text;
    _labelController.addListener(_edited);
    _register();
  }

  void _edited() {
    widget.callbacks.editSession?.markEdited();
  }

  bool get _composing => isTextInputComposing(_labelController);
  void _register() {
    widget.callbacks.editSession?.register(
      this,
      CanvasEditorFlush(isComposing: () => _composing, flush: _flush),
    );
  }

  void _background(Future<void> task) {
    unawaited(task.catchError((Object _) {}));
  }

  Future<void> _flush() async {
    if (_composing) {
      throw const CanvasEditSessionException('input_composing');
    }
    final value = _labelController.text;
    if (value == _savedLabel) {
      return;
    }
    final id = widget.edge.id;
    await widget.callbacks.onEdgeLabelChanged(id, value);
    if (mounted && widget.edge.id == id) {
      _savedLabel = value;
    }
  }

  @override
  void didUpdateWidget(_EdgeEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.callbacks.editSession != widget.callbacks.editSession) {
      oldWidget.callbacks.editSession?.unregister(this);
      _register();
    }
    if (oldWidget.edge.id != widget.edge.id) {
      if (!_composing && _labelController.text != _savedLabel) {
        _background(
          oldWidget.callbacks.onEdgeLabelChanged(
            oldWidget.edge.id,
            _labelController.text,
          ),
        );
      }
      _labelController.text = _savedLabel = widget.edge.label ?? '';
    } else if (!_composing && _labelController.text == _savedLabel) {
      final text = widget.edge.label ?? '';
      if (_labelController.text != text) {
        final selection = _labelController.selection;
        _labelController.value = TextEditingValue(
          text: text,
          selection: selection.isValid
              ? selection.copyWith(
                  baseOffset: selection.baseOffset.clamp(0, text.length),
                  extentOffset: selection.extentOffset.clamp(0, text.length),
                )
              : TextSelection.collapsed(offset: text.length),
        );
      }
      _savedLabel = text;
    }
  }

  @override
  void dispose() {
    widget.callbacks.editSession?.unregister(this);
    if (!_composing && _labelController.text != _savedLabel) {
      _background(
        widget.callbacks.onEdgeLabelChanged(
          widget.edge.id,
          _labelController.text,
        ),
      );
    }
    _labelController.removeListener(_edited);
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CanvasFloatingCard(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CanvasEdgeTypeList(
              value: widget.edge.type,
              onPick: (type) =>
                  widget.callbacks.onEdgeTypeChanged(widget.edge.id, type),
              compact: true,
            ),
            const SizedBox(height: RevericSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: RevericTextField(
                    controller: _labelController,
                    height: RevericSizes.fieldHeightSm,
                    style: RevericTheme.typographyOf(context).uiSmall,
                    hintText: context.t(LocaleKeys.canvasEdgeLabelHint),
                    onSubmitted: (_) {
                      if (!_composing) {
                        _background(_flush());
                      }
                    },
                    onTapOutside: (_) {
                      if (!_composing) {
                        _background(_flush());
                      }
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                  ),
                ),
                const SizedBox(width: RevericSpacing.xs),
                RevericMoreMenuButton(
                  iconSize: 16,
                  entries: () {
                    final colors = RevericTheme.colorsOf(context);
                    return [
                      RevericMenuItem(
                        icon: RevericIcons.delete_outline,
                        iconColor: colors.warningText,
                        labelColor: colors.warningText,
                        label: context.t(LocaleKeys.commonDelete),
                        onTap: () => _background(
                          _flush().then(
                            (_) =>
                                widget.callbacks.onDeleteEdge(widget.edge.id),
                          ),
                        ),
                      ),
                    ];
                  },
                ),
                CanvasIconButton(
                  icon: RevericIcons.close,
                  tooltip: context.t(LocaleKeys.commonClose),
                  onTap: widget.callbacks.onClearSelection,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
